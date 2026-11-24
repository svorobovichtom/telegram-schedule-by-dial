import UIKit

/// Telegram's timing. `.spring(duration: X)` and `.animated(duration: X, curve: .spring)` run a real spring only for
/// X = 0.5; any other duration is a CABasicAnimation with the bezier (0.38, 0.70, 0.125, 1.0) over X
/// (submodules/Display/Source/CAAnimationUtils.swift). Most "spring" transitions in the chat (0.35, 0.4, 0.42) are this.
@MainActor
public enum Motion {
    public static let springCurve = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.38, y: 0.70),
                                                            controlPoint2: CGPoint(x: 0.125, y: 1.0))

    /// Runs `animations` over `duration` with Telegram's "spring" bezier.
    public static func spring(_ duration: TimeInterval, delay: TimeInterval = 0, _ animations: @escaping () -> Void,
                              completion: ((Bool) -> Void)? = nil) {
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: springCurve)
        animator.addAnimations(animations)
        if let completion { animator.addCompletion { completion($0 == .end) } }
        animator.startAnimation(afterDelay: delay)
    }
}
