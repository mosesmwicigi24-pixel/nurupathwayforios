// Observable session state — the native counterpart of authSlice + the
// TokenVault bootstrap in the React Native app. Holds the signed-in flag and the
// /me profile, and drives Login ↔ Tab shell.
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    private var didRegisterDevice = false
    @Published var isAuthenticated = false
    @Published var me: MeResponse?
    @Published var booting = true

    var profile: UserProfile? { me?.profile }

    init() {
        Task { await bootstrap() }
    }

    /// On launch: if a token survived in the Keychain, treat the session as live
    /// (a stale access token is refreshed on the first request) and load /me.
    func bootstrap() async {
        await APIClient.shared.setOnSessionExpired { [weak self] in
            Task { @MainActor in self?.signOut() }
        }
        #if DEBUG
        // Headless smoke-testing hook (Debug only): inject a token via the launch
        // environment to start signed in. Compiled out of Release; no-op when unset.
        let env = ProcessInfo.processInfo.environment
        if let access = env["NURU_ACCESS_TOKEN"], !access.isEmpty {
            await APIClient.shared.setSession(access: access, refresh: env["NURU_REFRESH_TOKEN"])
            isAuthenticated = true
            await loadProfile()
            booting = false
            return
        }
        #endif
        if await APIClient.shared.hasSession {
            // Leave the splash IMMEDIATELY once we know a session exists — never gate
            // the whole app on the /me round-trip (which, on a real device with an
            // expired access token, first has to refresh; a slow or stalled network
            // would otherwise trap the user on the spinner). The profile — and any
            // token refresh — resolves in the background and fills in when it lands.
            isAuthenticated = true
            booting = false
            await loadProfile()
        } else {
            booting = false
        }
    }

    /// Called by LoginView once a full session is in hand.
    func onAuthenticated(_ session: Session) async {
        await APIClient.shared.setSession(access: session.accessToken, refresh: session.refreshToken)
        isAuthenticated = true
        await loadProfile()
    }

    func loadProfile() async {
        // Keep the last good profile on a transient failure — overwriting with
        // nil would blank role-gated UI (leader tools) mid-session.
        if let fresh = try? await MemberAPI.me() { me = fresh }
        // Device census (Android parity): platform + app version + model so
        // leadership's device analytics see iOS too. Fire-and-forget; the
        // push_token joins once APNs ships (paid Apple Developer Program).
        if me != nil, !didRegisterDevice {
            didRegisterDevice = true // once per launch — the census wants presence, not every /me refresh
            Task.detached { await MemberAPI.registerDevice() }
        }
    }

    func signOut() {
        Task { await APIClient.shared.clearSession() }
        me = nil
        isAuthenticated = false
    }
}
