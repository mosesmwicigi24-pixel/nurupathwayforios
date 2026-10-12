// The edge swipe back, on every stack (the walk's B9; §7.1 rule 3: every
// screen has a way out). Almost every pushed page hides the system back
// button and draws its own inside a hero — and hiding it turns the edge
// swipe off. Scrolled down a level page, the back had scrolled away with
// the hero and a swipe from the left did nothing; only another tab got out.
//
// `nuruEdgeSwipeBack()` on a stack's root finds that stack's navigation
// controller and answers its pop gesture itself: yes whenever something is
// pushed. No pushed page asks before leaving by its own back button either
// (the exit guards live on sheets and on actions), so the swipe opens no
// new way to lose what a member typed.
import SwiftUI
import UIKit

private struct EdgeSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.attach() }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attach()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }
        func attach() {
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.isEnabled = true
            pop.delegate = self
        }
        /// Back from anything pushed; never from a stack's root.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

extension View {
    /// Restores the edge swipe back on this stack's pushed pages (B9).
    func nuruEdgeSwipeBack() -> some View {
        background(EdgeSwipeBack().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
