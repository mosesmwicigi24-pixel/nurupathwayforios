// The lock on the pastoral door — Chat Redesign C3b.
//
// DELIBERATELY NOT BroadcastLock's shape. Broadcast's server routes demand a
// fresh password confirmation, so that lock stores the password behind Face ID
// and replays it. The member's own pastoral thread has NO server step-up —
// POST /chat/pastoral opens with an ordinary session — so this lock stores
// NOTHING. It is a pure local privacy gate: "the person holding this phone is
// its owner", answered by the OS (Face ID / Touch ID, falling back to the
// device passcode via LAPolicy.deviceOwnerAuthentication). No password in the
// keychain, no raw biometrics anywhere, nothing to steal.
//
// Once opened it stays open for 5 minutes — shorter than Broadcast's 15,
// because this guards a glance-over-the-shoulder risk, not broadcast authority
// — and re-seals the moment the app leaves the foreground, on timeout, and on
// sign-out. Device-specific by design: enabling it here says nothing about the
// member's other devices, and the server is never told.
import Foundation
import LocalAuthentication
import UIKit

@MainActor
final class PastoralLock: ObservableObject {
    static let shared = PastoralLock()

    /// Locked → OS auth → open until `until`. Nil = sealed.
    @Published private(set) var openUntil: Date?
    /// The member's choice, per device. Off by default — the ⋮ menu enables it.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "pastoral.lock.enabled"
    private let window: TimeInterval = 5 * 60

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        // Leaving the app re-seals the door — "re-auth on device-lock/restart"
        // falls out of this too, since both pass through backgrounding.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in PastoralLock.shared.relock() } }
    }

    var isOpen: Bool { (openUntil ?? .distantPast) > Date() }
    /// The gate is only closed when the member turned it on AND it isn't open.
    var requiresUnlock: Bool { isEnabled && !isOpen }

    /// What the OS will actually show — biometrics when enrolled, otherwise the
    /// device passcode. False only on devices with no passcode at all.
    static var deviceAuthAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "device passcode"
        }
    }

    /// Raise the OS prompt (Face ID → passcode fallback is the OS's own flow).
    /// True opens the window; false means cancelled/failed — stay sealed.
    func unlock(reason: String = "Open your private pastoral conversation") async -> Bool {
        guard Self.deviceAuthAvailable else {
            // No passcode set on the device — nothing the OS can gate with.
            // Fail OPEN with the member's intent (they own an unlocked phone),
            // rather than locking them out of their own pastoral care forever.
            markOpen()
            return true
        }
        do {
            try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            markOpen()
            return true
        } catch { return false }
    }

    func markOpen() { openUntil = Date().addingTimeInterval(window) }
    func relock() { openUntil = nil }

    /// Sign-out sweep — seal the door and forget this device's preference and
    /// remembered thread ids (the next account on this phone starts clean).
    func reset() {
        relock()
        isEnabled = false
        PastoralPrefs.reset()
    }
}

/// Small per-device store for what the client learned about its own private
/// threads. The inbox list endpoint doesn't carry the conversation `type`
/// (verified against chat/service.ts#listConversations), so once the app opens
/// the pastoral/discipler thread through its own tab it remembers the id —
/// that's how those threads keep their privacy dressing (and the pastoral lock)
/// when reached from anywhere else, and how they're kept out of the Chat tab's
/// ordinary DM list.
enum PastoralPrefs {
    private static let pastoralIdKey = "pastoral.conversationId"
    private static let disciplerIdKey = "discipler.conversationId"
    private static let mutedKey = "pastoral.muted"
    private static let archivedKey = "pastoral.archived"

    static var pastoralConversationId: String? {
        get { UserDefaults.standard.string(forKey: pastoralIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: pastoralIdKey) }
    }
    static var disciplerConversationId: String? {
        get { UserDefaults.standard.string(forKey: disciplerIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: disciplerIdKey) }
    }
    /// Mute is client-side: it silences the pastoral thread's contribution to
    /// tab badges. (iOS posts no per-message chat notifications at all — see
    /// LocalNotifier — so there is nothing further to silence on this device.)
    static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }
    /// Archive is a client-side hide of the member's own pastoral surface —
    /// the server keeps the thread; "Talk with My Pastor" offers to reopen it.
    static var archived: Bool {
        get { UserDefaults.standard.bool(forKey: archivedKey) }
        set { UserDefaults.standard.set(newValue, forKey: archivedKey) }
    }

    static func reset() {
        for k in [pastoralIdKey, disciplerIdKey, mutedKey, archivedKey] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
}
