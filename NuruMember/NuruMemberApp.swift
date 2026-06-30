// Native Nuru Place member app — SwiftUI entry. The native iOS replacement for
// the React Native member app (packages/mobile), over the same backend + OpenAPI
// contract. Login → five-tab shell, all in SwiftUI.
import SwiftUI
import UIKit

@main
struct NuruMemberApp: App {
    @StateObject private var auth = AuthStore()

    init() {
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
            .tint(Nuru.gold)
            // The app is designed in warm light tones; keep system chrome light.
            .preferredColorScheme(.light)
        }
    }

    /// App-wide chrome: brand-navy titles on warm paper bars.
    static func configureAppearance() {
        func font(_ name: String, _ size: CGFloat, _ fallback: UIFont.Weight) -> UIFont {
            UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: fallback)
        }
        let navy = UIColor(Nuru.navy)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Nuru.paper)
        appearance.shadowColor = .clear
        appearance.largeTitleTextAttributes = [.foregroundColor: navy, .font: font("Inter-SemiBold", 30, .semibold)]
        appearance.titleTextAttributes = [.foregroundColor: navy, .font: font("Inter-SemiBold", 17, .semibold)]
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
