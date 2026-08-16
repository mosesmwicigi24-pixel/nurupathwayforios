// Confirm it's you (§5.3 step-up).
//
// Being signed in is not the same claim as "the person holding this phone is the
// pastor". A handset left unlocked on a desk is already past login. So before it
// speaks to the whole church in your name — or opens what the church wrote back —
// the password is asked for once more, and the answer is good for 15 minutes.
//
// This is a door, not an error. It should read like being recognised, not like
// being refused.
import SwiftUI

struct PasswordConfirmSheet: View {
    /// Why we're asking, in the caller's own words — "to send this to everyone",
    /// "to open the answers". Named so the sheet never says a generic thing.
    let reason: String
    /// Called once the token carries a fresh confirmation; the caller retries.
    let onConfirmed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var focused: Bool
    /// Offer to remember the password behind Face ID / Touch ID so the next
    /// unlock is a glance, not typing. On by default where the hardware exists —
    /// the point of the ask was "fingerprint or camera or password".
    @State private var rememberWithBiometrics = BroadcastLock.biometryAvailable

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                HStack(alignment: .top, spacing: 14) {
                    Icon(.lock, size: 20, color: Color(hex: 0xE6C068))
                        .frame(width: 40, height: 40)
                        .background(Nuru.gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirm it's you").font(.nRowTitle).kerning(-0.16).foregroundStyle(.white)
                        Text(reason)
                            .font(.inter(11)).foregroundStyle(.white.opacity(0.7)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Nuru.S.base)
                .background(
                    LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                NuruField(placeholder: "Your password", text: $password, secure: true)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { Task { await confirm() } }
                    .disabled(busy)

                if let e = errorText {
                    HStack(spacing: 6) {
                        Icon(.shield, size: 13, color: Color(hex: 0xB91C1C))
                        Text(e).font(.inter(12, .medium)).foregroundStyle(Color(hex: 0xB91C1C))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }

                if BroadcastLock.biometryAvailable {
                    Toggle(isOn: $rememberWithBiometrics) {
                        Text("Unlock with \(BroadcastLock.biometryName) next time")
                            .font(.inter(13, .medium)).foregroundStyle(Nuru.navy)
                    }
                    .tint(Nuru.gold)
                }

                PButton(title: "Confirm", variant: .gold, busy: busy) {
                    Task { await confirm() }
                }
                .disabled(password.isEmpty || busy)
                .opacity(password.isEmpty ? 0.55 : 1)

                Text("Asked once every 15 minutes — never for reading your own conversations.")
                    .font(.nCardMeta).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Nuru.S.screen)
            .background(Nuru.paper.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.2), value: errorText == nil)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .font(.inter(14, .medium)).foregroundStyle(Nuru.ink600)
                }
            }
        }
        .presentationDetents([.height(400)])
        .onAppear { focused = true }
    }

    private func confirm() async {
        let entry = password
        guard !entry.isEmpty, !busy else { return }
        busy = true; errorText = nil
        defer { busy = false }
        do {
            try await MemberAPI.confirmPassword(entry)
            // The password is CONFIRMED RIGHT — the only moment it is safe to
            // put behind the owner's face for next time.
            if rememberWithBiometrics, BroadcastLock.biometryAvailable {
                BroadcastLock.enrollBiometricUnlock(password: entry)
            }
            BroadcastLock.shared.markOpen()
            password = ""
            Haptics.success()
            onConfirmed()
            dismiss()
        } catch let e as APIError {
            Haptics.error()
            // Say the true thing. A wrong password and a locked account are
            // different problems, and "try again" is bad advice for the second.
            if case let .http(status, _, message, _) = e {
                errorText = status == 429
                    ? message   // the server names the cooldown — do not paraphrase it
                    : status == 401 ? "That password isn't right." : message
            } else {
                errorText = "Couldn't reach the server. Check your connection."
            }
        } catch {
            Haptics.error()
            errorText = "Couldn't confirm just now — please try again."
        }
    }
}
