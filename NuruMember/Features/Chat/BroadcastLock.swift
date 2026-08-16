// The lock on the Broadcast door (§5.3 step-up).
//
// The SERVER only opens the Broadcast for a token carrying a fresh password
// confirmation — Face ID cannot answer that, because the server needs the
// password. So biometrics work the way a bank app's do: the FIRST unlock types
// the password and may store it in the keychain behind the Secure Enclave,
// releasable only by the owner's face or finger (biometryCurrentSet — enrolling
// a new face/finger invalidates it). From then on, tapping Broadcast raises
// Face ID, the enclave releases the password, and it is confirmed with the
// server silently. The server stays authoritative; biometrics carry the key.
//
// The unlock is remembered for the same 15 minutes the server honours, so the
// door doesn't re-lock between a send and reading the answers.
import Foundation
import LocalAuthentication
import Security

@MainActor
final class BroadcastLock: ObservableObject {
    /// One lock for the whole app: the composer's password sheet and the
    /// Broadcast section must agree on whether the door is open.
    static let shared = BroadcastLock()

    /// Locked → asking (Face ID or the sheet) → open until `until`.
    @Published private(set) var openUntil: Date?

    var isOpen: Bool { (openUntil ?? .distantPast) > Date() }

    /// Matches the server's requirePasswordStepUp window (900s), less a margin so
    /// the client never believes a token the server is about to refuse.
    private let window: TimeInterval = 15 * 60 - 30

    // MARK: Biometric-protected password (Secure Enclave)

    private static let service = "org.nuruplace.member.broadcast"
    private static let account = "step-up-password"

    /// Whether the device can do biometrics at all (Face ID / Touch ID enrolled).
    static var biometryAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// What to call it in copy — "Face ID" on the pastor's iPhone 17, "Touch ID"
    /// where that is what the hardware has.
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Face ID"
        }
    }

    /// Is a password stored behind biometrics? Checked WITHOUT prompting — an
    /// LAContext with interactionNotAllowed (the iOS 14+ replacement for the
    /// deprecated kSecUseAuthenticationUIFail): errSecInteractionNotAllowed
    /// means "it is there, but a face is needed to read it" — exactly a yes.
    static var biometricUnlockEnrolled: Bool {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: ctx,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecInteractionNotAllowed || status == errSecSuccess
    }

    /// Store the password behind the owner's CURRENT biometrics. Enrolling a new
    /// face or finger invalidates it (biometryCurrentSet) — someone added to the
    /// phone later can never inherit the Broadcast.
    static func enrollBiometricUnlock(password: String) {
        removeBiometricUnlock()
        guard let data = password.data(using: .utf8),
              let access = SecAccessControlCreateWithFlags(
                  nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil)
        else { return }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
            kSecAttrSynchronizable as String: false, // never to iCloud Keychain
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func removeBiometricUnlock() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Unlocking

    /// The face-first path: raise Face ID, let the enclave release the stored
    /// password, confirm it with the server. Returns false when the caller
    /// should fall back to the password sheet — face not recognised, nothing
    /// enrolled, or the STORED password no longer right (it was changed): in
    /// that last case the stale copy is removed so the next success re-enrolls.
    func unlockWithBiometrics() async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "" // our own sheet is the fallback, not the device passcode
        guard Self.biometricUnlockEnrolled else { return false }
        do {
            try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                         localizedReason: "Open the Broadcast")
        } catch { return false } // cancelled / not recognised → sheet
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: ctx,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else { return false }
        do {
            try await MemberAPI.confirmPassword(password)
            markOpen()
            return true
        } catch {
            // The password behind the face is no longer the account's password.
            // Drop it — holding a wrong one would burn lockout attempts silently.
            Self.removeBiometricUnlock()
            return false
        }
    }

    /// Called after ANY successful confirm — biometric or typed.
    func markOpen() {
        openUntil = Date().addingTimeInterval(window)
    }

    func relock() { openUntil = nil }
}
