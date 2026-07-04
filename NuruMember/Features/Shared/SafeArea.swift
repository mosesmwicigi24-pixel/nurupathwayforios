import UIKit

/// Top safe-area inset of the key window. Full-bleed headers sit under the
/// shell's paper status-bar stripe, so they must pad past the REAL inset —
/// a hard-coded 60 crops bell badges and progress rings on phones whose
/// Dynamic Island area is taller (e.g. iPhone 17 Pro Max at ~62pt).
enum NuruSafeArea {
    static var top: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 59
    }
}
