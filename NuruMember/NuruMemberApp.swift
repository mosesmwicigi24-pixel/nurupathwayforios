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
            .tint(Nuru.gold)
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
                } else {
                    // Signed out: the next member starts with nobody's dot.
                    InboxBadge.shared.reset()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, auth.isAuthenticated {
                    Task { await sync.flush() }
                    Task { await LocalNotifier.shared.sync() }
                }
            }
        }
    }

    /// App-wide chrome: brand-navy titles on warm paper bars, in the type
    /// scale's faces and steps (EXPERIENCE.md §8.1 rule 3) — never the system
    /// face, even for a bar button.
    static func configureAppearance() {
        let navy = UIColor(Nuru.navy)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Nuru.paper)
        appearance.shadowColor = .clear
        appearance.largeTitleTextAttributes = [.foregroundColor: navy, .font: Nuru.uiFont("Inter-SemiBold", 28)]
        appearance.titleTextAttributes = [.foregroundColor: navy, .font: Nuru.uiFont("Inter-SemiBold", 16)]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: Nuru.uiFont("Inter-SemiBold", 16)]
        appearance.buttonAppearance = button
        appearance.doneButtonAppearance = button
        appearance.backButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(Nuru.gold)
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
