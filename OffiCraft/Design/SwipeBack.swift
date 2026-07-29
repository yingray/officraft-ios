import SwiftUI
import UIKit
import ObjectiveC

/// Restores the edge-swipe back gesture on screens that hide the navigation bar.
///
/// Every pushed screen in this app draws its own header, so they all set
/// `navigationBarHidden(true)` — and UIKit switches off
/// `interactivePopGestureRecognizer` whenever the bar is hidden, because
/// normally there would be no back button to justify it. The custom header has
/// one, so the gesture should stay: swiping right from the left edge is how
/// people go back on iOS, and losing it makes every screen a dead end but for
/// one small target in the corner.
///
/// The delegate has to answer "may this gesture begin?" — pop at the root and
/// UIKit wedges the navigation stack — so it is not enough to just re-enable
/// the recogniser.
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        // Nothing to pop, or a push/pop already running: both wedge the stack.
        return navigationController.viewControllers.count > 1
            && navigationController.transitionCoordinator == nil
    }

    /// The transcript and every other screen sit in a scroll view. Letting both
    /// recognisers run turns a horizontal swipe into a scroll-and-pop at once.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }
}

private var swipeBackDelegateKey: UInt8 = 0

private extension UINavigationController {
    /// Installed once per navigation controller and kept alive by it — the
    /// recogniser holds its delegate weakly, so a delegate owned by the screen
    /// would vanish on pop and leave the gesture with no delegate at all.
    func installSwipeBackDelegate() {
        if let existing = objc_getAssociatedObject(self, &swipeBackDelegateKey) as? SwipeBackDelegate {
            interactivePopGestureRecognizer?.delegate = existing
            interactivePopGestureRecognizer?.isEnabled = true
            return
        }
        let delegate = SwipeBackDelegate()
        delegate.navigationController = self
        objc_setAssociatedObject(self, &swipeBackDelegateKey, delegate,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        interactivePopGestureRecognizer?.delegate = delegate
        interactivePopGestureRecognizer?.isEnabled = true
    }
}

/// Finds the enclosing `UINavigationController` and re-arms its pop gesture.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Probe() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    final class Probe: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            arm()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Also on appear: a screen can be built before it is in a stack,
            // and coming back from a deeper push re-runs this but not didMove.
            arm()
        }

        /// `navigationController` already walks the parent chain for us.
        private func arm() {
            navigationController?.installSwipeBackDelegate()
        }
    }
}

extension View {
    /// Put this on any screen that hides the navigation bar but still offers a
    /// back button of its own.
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
