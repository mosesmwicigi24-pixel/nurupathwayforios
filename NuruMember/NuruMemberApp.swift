// Native Nuru Place member app — SwiftUI entry. The native iOS replacement for
// the React Native member app (packages/mobile), over the same backend + OpenAPI
// contract. Login → five-tab shell, all in SwiftUI.
import SwiftUI
import UIKit

@main
struct NuruMemberApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var sync = SyncCoordinator.shared
    @StateObject private var tabs = TabRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Crash-reporting bring-up: safe no-op until a real
        // GoogleService-Info.plist exists (see CrashReporting.swift).
        CrashReporting.configureIfAvailable()
        configureNuruCaches()
        Nuru.registerFonts()
        Self.configureAppearance()
        Self.followTextSize()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.booting {
                    SplashView()
                } else if auth.isAuthenticated {
                    RootView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(auth)
            .environmentObject(sync)
            .environmentObject(tabs)
            // Text with no font of its own is the body, never the system face.
            .nuruDefaultFont()
            // The system's own chrome — an alert's or a dialog's answers, a
            // menu, a toolbar's word, a caret — takes this tint: navy, the
            // chrome colour (§8.1 rule 1; final walk M5: gold answers read
            // about 1.05:1 on the alert's glass). Gold stays where a view sets
            // it: a selected switch, a picker, the primary action.
            .tint(Nuru.navy)
            // The app is designed in warm light tones; keep system chrome light.
            .preferredColorScheme(.light)
            // Start the offline sync engine once we're authenticated; drain the
            // durable queue whenever the app returns to the foreground.
            .task(id: auth.isAuthenticated) {
                if auth.isAuthenticated {
                    sync.start()
                    // Real iOS notifications: surface any new server
                    // notifications with banner + sound (vibration on silent)
                    // into the phone's Notification Center — once the member
                    // has allowed them. Nothing asks here: permission is asked
                    // only when they turn on something that needs it (§7.2 #12).
                    LocalNotifier.shared.attach()
                    await LocalNotifier.shared.sync()
                    // Whether a discipler is paired — every offer of one waits
                    // for the server to name one (Cycle 4, B1).
                    await DisciplerStore.shared.refresh()
                } else {
                    // Signed out: the next member starts with nobody's dot,
                    // and nobody's discipler.
                    InboxBadge.shared.reset()
                    DisciplerStore.shared.reset()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, auth.isAuthenticated {
                    Task { await sync.flush() }
                    Task { await LocalNotifier.shared.sync() }
                    Task { await DisciplerStore.shared.refresh() }
                }
            }
        }
    }

    /// The bars carry the member's own text size, as everything else does:
    /// set again the moment it changes — before RootView rebuilds under its
    /// new `.id(textScale)` — so every bar made after has it, the tabs' and
    /// every sheet's. (They kept 16 pt whatever the size: the Cycle 5–10
    /// text-size audit, 2026-10-07.)
    static func followTextSize() {
        var applied = Nuru.textScale
        textSizeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: nil
        ) { _ in
            let now = Nuru.textScale
            guard now != applied else { return }
            applied = now
            if Thread.isMainThread {
                MainActor.assumeIsolated { configureAppearance() }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { configureAppearance() } }
            }
        }
    }
    nonisolated(unsafe) private static var textSizeObserver: NSObjectProtocol?

    /// App-wide chrome: brand-navy titles on warm paper bars, in the type
    /// scale's faces and steps (EXPERIENCE.md §8.1 rule 3) — never the system
    /// face, even for a bar button — at the member's own text size.
    static func configureAppearance() {
        let navy = UIColor(Nuru.navy)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Nuru.paper)
        appearance.shadowColor = .clear
        appearance.largeTitleTextAttributes = [.foregroundColor: navy, .font: Nuru.uiFont("Inter-SemiBold", 28, scaled: true)]
        appearance.titleTextAttributes = [.foregroundColor: navy, .font: Nuru.uiFont("Inter-SemiBold", 16, scaled: true)]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: Nuru.uiFont("Inter-SemiBold", 16, scaled: true)]
        appearance.buttonAppearance = button
        appearance.doneButtonAppearance = button
        appearance.backButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(Nuru.gold)
        // System alerts, confirmation dialogs and menus answer in the app's
        // accent, which is navy (Assets: AccentColor; final walk M5): gold
        // read about 1.05:1 on their grey glass — "Keep it private" before a
        // private prayer goes congregation-wide. iOS 26 sets an alert's tint
        // from SwiftUI's accent, so no appearance proxy reaches it. Navy is
        // chrome (§8.1 rule 1); gold stays where the app sets it — selected
        // toggles, pickers, the primary action. A destructive answer keeps
        // the system's red.
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Nuru.ceremonyGradient.ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark(size: 72)
                ProgressView().tint(.white)
            }
        }
    }
}
