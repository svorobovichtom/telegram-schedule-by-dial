import UIKit
import TelegramShell

/// The dial that grows around Send on Telegram's send-options screen once the held finger leaves Send: a ring
/// around Send whose stops sit on the quarter from the left of Send up to above it, one per preset and "Custom" last.
/// The ring itself runs on past both ends and fades out (above Send it leaves the screen), with a scale of ticks
/// around its outside (two between stops, a longer one at each stop), so it reads as a piece of a bigger dial, not
/// a pill. The fill ends in a round cap that wraps the knob like a halo and travels with it; a pointer on the scale
/// follows the knob too. The finger's direction from Send picks the stop
/// (its distance only has to clear the button), so a thumb sweeps through them in one arc. The knob follows the
/// finger but clings to the stops, like a detent, and each stop gives a click.
///
/// It lives in `SendMenuView.featureContainer`, so the screen's blur and dim are under it and the screen's Send and
/// preview bubble over it. Coordinates are the screen's. The hint (what the picked stop means) sits left of the ring,
/// where the thumb doesn't cover it, and stays put; only its changed characters roll.
@MainActor
final class DialView: UIView {
    // Geometry. Angles are in degrees, counter-clockwise from the right (180 = left of Send, 90 = above it).
    static let radius: CGFloat = 160
    static let trackWidth: CGFloat = 50
    static let startAngle: CGFloat = 180
    static let endAngle: CGFloat = 90
    /// How far the track runs past the first and last stop: solid for `solidOverrun`, then fading out to `overrun`.
    static let overrun: CGFloat = 45
    static let solidOverrun: CGFloat = 10
    /// The finger has to be this far from Send to open the dial; closer than `releaseRadius` it closes again.
    static let pickRadius: CGFloat = 48
    static let releaseRadius: CGFloat = 34
    static var outerRadius: CGFloat { radius + trackWidth / 2 }
    /// The scale outside the band: ticks start `tickGap` off the edge; the long ones end at `scaleRadius`.
    static let tickGap: CGFloat = 4
    static let minorTick: CGFloat = 3.5
    static let majorTick: CGFloat = 7
    static var scaleRadius: CGFloat { outerRadius + tickGap + majorTick }

    let stops: [ScheduleStop]
    let now: Date
    let sendCenter: CGPoint
    private let theme: Theme

    /// The stop under the finger; nil once the finger is back over Send.
    private(set) var selectedIndex: Int?
    var selection: ScheduleStop? { selectedIndex.map { stops[$0] } }
    /// Called whenever the picked stop changes, with the direction it moved along the ring.
    var onSelect: ((ScheduleStop?, RollingLabel.Direction) -> Void)?

    /// The top of the ring, for whoever lays things out above it.
    var ringTop: CGFloat { sendCenter.y - Self.scaleRadius }

    private let ring = UIView()
    /// Track, fill, rims and ticks; masked so they fade out past the ends.
    private let fadingLayer = CALayer()
    private let trackLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let rimLayer = CAShapeLayer()
    private let minorTicks = CAShapeLayer()
    private let majorTicks = CAShapeLayer()
    /// The mark on the scale that travels with the knob.
    private let pointerLayer = CAShapeLayer()
    private var marks: [UIView] = []
    private let knob = UIView()
    private var knobMark = UIView()
    private let hint = UIView()
    private let hintTitle: RollingLabel
    private let hintDetail: RollingLabel

    /// The click of a detent: a short rigid tap as the knob takes a stop.
    private let detentFeedback = UIImpactFeedbackGenerator(style: .rigid)

    // The knob's angle follows the finger, pulled toward the nearest stop (see `track`), through a critically damped
    // spring: it travels along the ring and settles without overshoot.
    private var knobAngle: CGFloat = 180
    private var knobVelocity: CGFloat = 0
    private var targetAngle: CGFloat = 180
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    init(frame: CGRect, sendCenter: CGPoint, theme: Theme, now: Date = Date()) {
        self.sendCenter = sendCenter
        self.theme = theme
        self.now = now
        self.stops = ScheduleStop.stops(from: now)
        let textColor = theme.isDark ? UIColor.white : theme.controlColor
        hintTitle = RollingLabel(font: .monospacedDigitSystemFont(ofSize: 20, weight: .semibold), textColor: textColor, alignment: .right)
        hintDetail = RollingLabel(font: .monospacedDigitSystemFont(ofSize: 15, weight: .regular),
                                  textColor: textColor.withAlphaComponent(0.65), alignment: .right)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0

        let side = 2 * (Self.scaleRadius + 4)
        ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ring.center = sendCenter
        addSubview(ring)

        let middle = CGPoint(x: side / 2, y: side / 2)
        let from = Self.startAngle + Self.overrun, to = Self.endAngle - Self.overrun
        func arc(_ radius: CGFloat) -> UIBezierPath {
            UIBezierPath(arcCenter: middle, radius: radius, startAngle: -from * .pi / 180, endAngle: -to * .pi / 180, clockwise: true)
        }
        fadingLayer.frame = ring.bounds
        ring.layer.addSublayer(fadingLayer)
        let ink = theme.isDark ? UIColor.white : UIColor.black
        for (layer, color) in [(trackLayer, theme.isDark ? UIColor(white: 1, alpha: 0.1) : UIColor(white: 1, alpha: 0.45)),
                               (fillLayer, theme.sendFill.withAlphaComponent(theme.isDark ? 0.34 : 0.3))] {
            layer.path = arc(Self.radius).cgPath
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = Self.trackWidth
            fadingLayer.addSublayer(layer)
        }
        // The fill's round end is the halo around the knob (its other end is out in the fade).
        fillLayer.lineCap = .round
        fillLayer.strokeEnd = 0

        // A hairline along both edges, as glass has.
        let rims = arc(Self.outerRadius)
        rims.append(arc(Self.radius - Self.trackWidth / 2))
        rimLayer.path = rims.cgPath
        rimLayer.fillColor = nil
        rimLayer.strokeColor = (theme.isDark ? UIColor(white: 1, alpha: 0.14) : UIColor(white: 1, alpha: 0.6)).cgColor
        rimLayer.lineWidth = 0.5
        fadingLayer.addSublayer(rimLayer)

        // The scale, outside the band so the knob never covers it: counted from the first stop in thirds of a step,
        // so every third tick sits exactly on a stop (those are longer and brighter). It runs on into the fade.
        let step = (Self.startAngle - Self.endAngle) / CGFloat(max(1, stops.count - 1))
        let minor = UIBezierPath(), major = UIBezierPath()
        let inner = Self.outerRadius + Self.tickGap
        let before = Int((Self.overrun / (step / 3)).rounded(.down))
        for k in -before...(3 * (stops.count - 1) + before) {
            let onStop = k % 3 == 0 && k >= 0 && k <= 3 * (stops.count - 1)
            let r = (Self.startAngle - CGFloat(k) * step / 3) * .pi / 180
            let outer = inner + (onStop ? Self.majorTick : Self.minorTick)
            let path = onStop ? major : minor
            path.move(to: CGPoint(x: middle.x + inner * cos(r), y: middle.y - inner * sin(r)))
            path.addLine(to: CGPoint(x: middle.x + outer * cos(r), y: middle.y - outer * sin(r)))
        }
        for (layer, path, alpha) in [(minorTicks, minor, 0.22), (majorTicks, major, 0.55)] {
            layer.path = path.cgPath
            layer.strokeColor = ink.withAlphaComponent(alpha).cgColor
            layer.lineWidth = 1
            layer.lineCap = .round
            fadingLayer.addSublayer(layer)
        }

        // The pointer: drawn at angle 0 (right of Send) and turned to the knob's angle.
        let pointer = UIBezierPath()
        pointer.move(to: CGPoint(x: middle.x + inner, y: middle.y))
        pointer.addLine(to: CGPoint(x: middle.x + inner + Self.majorTick, y: middle.y))
        pointerLayer.frame = ring.bounds
        pointerLayer.path = pointer.cgPath
        pointerLayer.strokeColor = theme.sendFill.cgColor
        pointerLayer.lineWidth = 2.5
        pointerLayer.lineCap = .round
        pointerLayer.opacity = 0
        ring.layer.addSublayer(pointerLayer)

        // The fade: a conic gradient around Send. It starts pointing down and turns clockwise on screen, so an angle
        // θ (counter-clockwise from the right) sits at (270 − θ) / 360.
        let fade = CAGradientLayer()
        fade.type = .conic
        fade.frame = ring.bounds
        fade.startPoint = CGPoint(x: 0.5, y: 0.5)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        let at = { (angle: CGFloat) in NSNumber(value: Double((270 - angle) / 360)) }
        fade.colors = [0, 0, 1, 1, 0, 0].map { UIColor(white: 0, alpha: $0).cgColor }
        fade.locations = [0, at(from), at(Self.startAngle + Self.solidOverrun), at(Self.endAngle - Self.solidOverrun), at(to), 1]
        fadingLayer.mask = fade

        for (i, stop) in stops.enumerated() {
            let mark = Self.makeMark(stop.mark, color: textColor, size: 14)
            mark.alpha = Self.aheadAlpha
            mark.center = point(angle: angle(ofStop: i), radius: Self.radius, inRing: true)
            ring.addSubview(mark)
            marks.append(mark)
        }

        // 4pt smaller than the band all round: that ring of fill is its halo.
        knob.bounds = CGRect(x: 0, y: 0, width: Self.trackWidth - 8, height: Self.trackWidth - 8)
        knob.layer.cornerRadius = knob.bounds.height / 2
        knob.backgroundColor = theme.sendFill
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.18
        knob.layer.shadowRadius = 5
        knob.layer.shadowOffset = CGSize(width: 0, height: 1)
        knob.alpha = 0
        ring.addSubview(knob)

        hint.addSubview(hintTitle)
        hint.addSubview(hintDetail)
        addSubview(hint)
        layoutHint()
        layoutKnob()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Marks the knob has passed are bright, the ones ahead dimmer.
    private static let passedAlpha: CGFloat = 0.95
    private static let aheadAlpha: CGFloat = 0.55

    private func markAlpha(_ i: Int) -> CGFloat {
        guard let selectedIndex else { return Self.aheadAlpha }
        if i == selectedIndex { return 0 }
        return i < selectedIndex ? Self.passedAlpha : Self.aheadAlpha
    }

    // MARK: Geometry

    private func angle(ofStop index: Int) -> CGFloat {
        guard stops.count > 1 else { return Self.startAngle }
        return Self.startAngle + (Self.endAngle - Self.startAngle) * CGFloat(index) / CGFloat(stops.count - 1)
    }

    /// A point on the circle around Send, in this view's coordinates (or the ring's).
    private func point(angle: CGFloat, radius: CGFloat, inRing: Bool = false) -> CGPoint {
        let origin = inRing ? CGPoint(x: ring.bounds.midX, y: ring.bounds.midY) : sendCenter
        let a = angle * .pi / 180
        return CGPoint(x: origin.x + radius * cos(a), y: origin.y - radius * sin(a))
    }

    private static func makeMark(_ mark: ScheduleStop.Mark, color: UIColor, size: CGFloat) -> UIView {
        switch mark {
        case .text(let text):
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: size, weight: .semibold)
            label.textColor = color
            label.sizeToFit()
            return label
        case .symbol(let name):
            let view = UIImageView(image: UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)))
            view.tintColor = color
            view.sizeToFit()
            return view
        }
    }

    /// Left of the ring, its right edge 16pt clear of the ring's outside at the hint's height, lines right-aligned.
    private func layoutHint() {
        let titleHeight = hintTitle.lineHeight, detailHeight = hintDetail.lineHeight
        let height = titleHeight + 2 + detailHeight
        let midY = sendCenter.y - Self.radius * 0.75
        // The ring reaches furthest left at the hint's bottom edge.
        let dy = max(sendCenter.y - (midY + height / 2), 0)
        let ringLeft = sendCenter.x - sqrt(max(0, Self.scaleRadius * Self.scaleRadius - dy * dy))
        let right = ringLeft - 16
        let left: CGFloat = 16
        hint.frame = CGRect(x: left, y: midY - height / 2, width: max(0, right - left), height: height)
        hintTitle.frame = CGRect(x: 0, y: 0, width: hint.bounds.width, height: titleHeight)
        hintDetail.frame = CGRect(x: 0, y: titleHeight + 2, width: hint.bounds.width, height: detailHeight)
    }

    // MARK: Showing

    /// Grows out of Send: the ring scales up from Send's middle, the track draws itself from the left, the marks
    /// fade in after it. Telegram's .spring curve throughout, so nothing bounces.
    func show() {
        detentFeedback.prepare()
        alpha = 1
        ring.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        ring.alpha = 0
        hint.alpha = 0
        hint.transform = CGAffineTransform(translationX: 12, y: 0)
        Motion.spring(0.4) {
            self.ring.transform = .identity
            self.ring.alpha = 1
        }
        Motion.spring(0.35, delay: 0.05) {
            self.hint.alpha = 1
            self.hint.transform = .identity
        }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.4
        draw.timingFunction = CAMediaTimingFunction(controlPoints: 0.38, 0.7, 0.125, 1)
        trackLayer.add(draw, forKey: "draw")
        let ticks = CABasicAnimation(keyPath: "opacity")
        ticks.fromValue = 0
        ticks.toValue = 1
        ticks.duration = 0.3
        ticks.beginTime = CACurrentMediaTime() + 0.1
        ticks.fillMode = .backwards
        minorTicks.add(ticks, forKey: "in")
        majorTicks.add(ticks, forKey: "in")
        for (i, mark) in marks.enumerated() {
            mark.alpha = 0
            UIView.animate(withDuration: 0.2, delay: 0.04 + 0.03 * Double(i), options: [.curveEaseOut]) {
                mark.alpha = self.markAlpha(i)
            }
        }
        if displayLink == nil {
            let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
        }
    }

    /// Folds back into Send.
    func hide() {
        select(nil, feedback: false)
        Motion.spring(0.3) {
            self.ring.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            self.ring.alpha = 0
            self.hint.alpha = 0
            self.hint.transform = CGAffineTransform(translationX: 12, y: 0)
        }
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: Tracking

    /// The finger, in screen coordinates.
    func track(_ finger: CGPoint) {
        let dx = finger.x - sendCenter.x, dy = sendCenter.y - finger.y
        guard hypot(dx, dy) >= Self.releaseRadius else {
            select(nil)
            return
        }
        var a = atan2(dy, dx) * 180 / .pi
        if a < 0 { a += 360 }
        // Below the left end: the first stop. Right of the top end (and the bottom right): the last.
        if a > Self.startAngle && a <= 270 { a = Self.startAngle }
        if a > 270 || a < Self.endAngle { a = Self.endAngle }
        let step = (Self.startAngle - Self.endAngle) / CGFloat(max(1, stops.count - 1))
        let position = (Self.startAngle - a) / step
        // The stop changes a little past halfway to the next one, so it doesn't flicker on the border.
        var index = selectedIndex ?? Int(position.rounded())
        if abs(position - CGFloat(index)) > 0.58 { index = Int(position.rounded()) }
        // The detent: near a stop the knob barely leaves it, then crosses to the next one quickly.
        let offset = min(0.5, max(-0.5, position - CGFloat(index)))
        let pulled = (offset < 0 ? -0.5 : 0.5) * pow(2 * abs(offset), 3)
        targetAngle = Self.startAngle - (CGFloat(index) + pulled) * step
        select(index)
    }

    private func select(_ index: Int?, feedback: Bool = true) {
        guard index != selectedIndex else { return }
        let previous = selectedIndex
        selectedIndex = index
        if feedback, index != nil {
            detentFeedback.impactOccurred(intensity: 0.75)
            detentFeedback.prepare()
        }
        let direction: RollingLabel.Direction = (index ?? 0) >= (previous ?? 0) ? .up : .down
        if let index {
            if previous == nil {
                knobAngle = targetAngle
                knobVelocity = 0
                layoutKnob()
            }
            let mark = Self.makeMark(stops[index].mark, color: theme.sendIcon, size: 15)
            mark.center = CGPoint(x: knob.bounds.midX, y: knob.bounds.midY)
            mark.alpha = 0
            knob.addSubview(mark)
            let old = knobMark
            knobMark = mark
            UIView.animate(withDuration: 0.15) {
                old.alpha = 0
                mark.alpha = 1
            } completion: { _ in old.removeFromSuperview() }
            let stop = stops[index]
            hintTitle.setText(stop.relative, direction: direction)
            hintDetail.setText(stop.detail(now: now), direction: direction)
        }
        let picked = index != nil
        Motion.spring(0.25) {
            self.knob.alpha = picked ? 1 : 0
            self.knob.transform = picked ? .identity : CGAffineTransform(scaleX: 0.6, y: 0.6)
        }
        UIView.animate(withDuration: 0.15) {
            for (i, mark) in self.marks.enumerated() { mark.alpha = self.markAlpha(i) }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        pointerLayer.opacity = picked ? 1 : 0
        if !picked { fillLayer.strokeEnd = 0 }
        CATransaction.commit()
        onSelect?(selection, direction)
    }

    private func layoutKnob() {
        knob.center = point(angle: knobAngle, radius: Self.radius, inRing: true)
        guard selectedIndex != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointerLayer.setAffineTransform(CGAffineTransform(rotationAngle: -knobAngle * .pi / 180))
        // The fill starts where the track does, in the fade below the first stop.
        fillLayer.strokeEnd = (Self.startAngle + Self.overrun - knobAngle) / (Self.startAngle - Self.endAngle + 2 * Self.overrun)
        CATransaction.commit()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? 1 / 60 : min(1 / 30, link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        let stiffness: CGFloat = 900, damping = 2 * sqrt(stiffness)
        let force = -stiffness * (knobAngle - targetAngle) - damping * knobVelocity
        knobVelocity += force * CGFloat(dt)
        knobAngle += knobVelocity * CGFloat(dt)
        layoutKnob()
    }
}

/// CADisplayLink retains its target; this keeps the dial free to go.
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var dial: DialView?
    init(_ dial: DialView) { self.dial = dial }
    @objc func tick(_ link: CADisplayLink) {
        guard let dial else { link.invalidate(); return }
        dial.tick(link)
    }
}
