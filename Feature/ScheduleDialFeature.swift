import UIKit
import TelegramShell

/// Schedule by Dial. Today holding Send opens Telegram's send-options screen: the text turns into a bubble, effects
/// above, "Send Without Sound / Schedule Message" below; Schedule Message opens a calendar. The concept keeps that
/// screen and adds one move to it: slide the held finger off Send, up or left, and the menu gives way to a dial
/// around Send (15 min, 30 min, 1 h, 3 h, tonight, tomorrow morning, Custom). The bubble moves above the dial and
/// shows the time it will go out; let go and it flies into the scheduled-messages clock. "Custom" opens the same
/// calendar as Schedule Message. Back over Send and the menu returns; let go without moving and it stays, as today.
///
/// Where it would hook into Telegram-iOS: ChatSendMessageContextScreen (the screen; its finger tracking at :362-391
/// is where the dial takes over) and ChatController's scheduled-message path for the chosen time, without
/// presentScheduleTimePicker for the presets.
///
/// Launch with `-scenario` to play the demo without touching the screen: it types, holds Send (the menu opens),
/// slides onto the dial to "1 h" and lets go; then a second message sweeps to "Custom", back to "tomorrow morning"
/// and is scheduled. It draws the finger.
@MainActor
final class ScheduleDialFeature: NSObject, ChatFeature {
    private weak var chat: ChatViewController?
    private weak var menu: SendMenuView?
    private weak var dial: DialView?
    private weak var timeLabel: RollingLabel?
    private weak var clockIcon: UIImageView?
    private var dialOpen = false
    private var toast: UIView?

    func chatDidLoad(_ chat: ChatViewController) {
        self.chat = chat
        // The same hold that opens the send options (Shell handles it first: it opens the screen and tracks the menu).
        chat.sendMenuGesture.addTarget(self, action: #selector(handleHold(_:)))
        // The calendar path (Schedule Message, or Custom on the dial) ends here too.
        chat.onScheduleMessage = { [weak self] text, date in self?.scheduledInCalendar(text, at: date) }

        if ProcessInfo.processInfo.arguments.contains("-scenario") {
            Task { @MainActor in await self.scenario(chat) }
        }
    }

    @objc private func handleHold(_ hold: UILongPressGestureRecognizer) {
        let point = hold.location(in: nil)
        switch hold.state {
        case .began: menuOpened()
        case .changed: fingerMoved(point)
        case .ended: fingerLifted()
        case .cancelled, .failed: setDial(open: false)
        default: break
        }
    }

    // MARK: Finger (also driven by the scenario)

    private func menuOpened() {
        menu = chat?.sendMenu
        dial = nil
        clockIcon = nil
        dialOpen = false
    }

    /// `point` in screen coordinates.
    private func fingerMoved(_ point: CGPoint) {
        guard let menu else { return }
        let send = menu.sourceSendCenter
        if !dialOpen {
            // Up or left of Send opens the dial; down toward the menu stays the menu's (as today).
            let distance = hypot(point.x - send.x, point.y - send.y)
            guard distance >= DialView.pickRadius, point.y < send.y + 12 else { return }
            setDial(open: true)
        }
        dial?.track(point)
        if dial?.selectedIndex == nil { setDial(open: false) }
    }

    private func fingerLifted() {
        guard dialOpen, let menu, let stop = dial?.selection else { return }
        dialOpen = false
        if stop.isCustom {
            // Exactly what Schedule Message does today: the field comes back, the calendar opens.
            menu.onAction?(.schedule)
        } else if let date = stop.date, let chat {
            schedule(menu, at: date, in: chat)
        }
    }

    // MARK: The dial on the send-options screen

    private func setDial(open: Bool) {
        guard let menu, let chat, open != dialOpen else { return }
        dialOpen = open
        menu.tracksFinger = !open
        menu.setOptionsHidden(open, animated: true)
        let bubble = menu.previewBubble
        let clock = clockIcon ?? addClock(to: menu, theme: chat.theme)

        if open {
            let dial = self.dial ?? addDial(to: menu, theme: chat.theme)
            dial.show()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // The bubble gets the time a scheduled message shows (MessageView's date: 11pt, secondary color) and
            // moves above the ring, right edge where it was.
            let label = RollingLabel(font: .monospacedDigitSystemFont(ofSize: Metrics.dateFont.pointSize, weight: .regular),
                                     textColor: chat.theme.outgoing.secondaryText, alignment: .right)
            timeLabel = label
            let size = bubble.setTrailing(label, size: CGSize(width: label.width(of: "00:00"), height: label.lineHeight))
            let frame = CGRect(x: menu.sourceSendFrame.minX + 3 - size.width, y: dial.ringTop - 14 - size.height,
                               width: size.width, height: size.height)
            Motion.spring(0.4) {
                bubble.frame = frame
                bubble.layoutIfNeeded()
            }
        } else {
            dial?.hide()
            // The time fades where it is; the bubble goes back to its menu place (SendMenuView moves it).
            if let label = timeLabel, let ghost = label.snapshotView(afterScreenUpdates: false) {
                ghost.frame = label.frame
                bubble.addSubview(ghost)
                UIView.animate(withDuration: 0.15) { ghost.alpha = 0 } completion: { _ in ghost.removeFromSuperview() }
            }
            bubble.setTrailing(nil, size: .zero)
            timeLabel = nil
        }
        // Send's arrow turns into the clock while the dial is open.
        Motion.spring(0.25) {
            menu.sendIconView.alpha = open ? 0 : 1
            menu.sendIconView.transform = open ? CGAffineTransform(scaleX: 0.5, y: 0.5) : .identity
            clock.alpha = open ? 1 : 0
            clock.transform = open ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
    }

    private func addDial(to menu: SendMenuView, theme: Theme) -> DialView {
        let dial = DialView(frame: menu.featureContainer.bounds, sendCenter: menu.sourceSendCenter, theme: theme)
        menu.featureContainer.addSubview(dial)
        dial.onSelect = { [weak self] stop, direction in
            guard let label = self?.timeLabel, let stop else { return }
            if let date = stop.date {
                label.setText(ScheduleStop.timeFormatter.string(from: date), direction: direction)
            }
            // Custom has no time yet.
            UIView.animate(withDuration: 0.15) { label.alpha = stop.isCustom ? 0 : 1 }
        }
        self.dial = dial
        return dial
    }

    private func addClock(to menu: SendMenuView, theme: Theme) -> UIImageView {
        let clock = UIImageView(image: Graphics.asset("TGAccessoryIconSchedule")?.withRenderingMode(.alwaysTemplate))
        clock.tintColor = theme.sendIcon
        clock.contentMode = .center
        clock.frame = menu.sendCopy.bounds
        clock.alpha = 0
        clock.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        menu.sendCopy.addSubview(clock)
        clockIcon = clock
        return clock
    }

    // MARK: Scheduling

    /// A preset: the bubble leaves the screen as it is and dives into the clock in the field.
    private func schedule(_ menu: SendMenuView, at date: Date, in chat: ChatViewController) {
        let overlay = chat.overlayView
        let panel = chat.inputPanel
        let bubble = menu.previewBubble
        let frame = bubble.layer.presentation()?.frame ?? bubble.frame
        let flyer = bubble.snapshotView(afterScreenUpdates: false) ?? UIView()
        flyer.frame = overlay.convert(frame, from: nil)
        flyer.isUserInteractionEnabled = false
        overlay.addSubview(flyer)
        bubble.alpha = 0

        // The field empties as the message leaves. Where the clock will be: lay the panel out with it, read it,
        // put the panel back; it appears as the bubble lands.
        let hadClock = panel.hasScheduledMessages
        panel.text = ""
        panel.setHasScheduledMessages(true, animated: false)
        let clock = panel.scheduleButton
        let target = overlay.convert(CGPoint(x: clock.bounds.midX, y: clock.bounds.midY), from: clock)
        if !hadClock { panel.setHasScheduledMessages(false, animated: false) }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        menu.dismiss(.handOff)
        let now = dial?.now ?? Date()
        dive(flyer, to: target) {
            flyer.removeFromSuperview()
            self.land(on: clock, appear: !hadClock)
            self.showToast("Scheduled for " + ScheduleStop.phrase(for: date, now: now), in: chat)
        }
    }

    /// The calendar path (Schedule Message, or Custom): the sheet has closed, the text is still in the field.
    private func scheduledInCalendar(_ text: String, at date: Date) {
        guard let chat else { return }
        let panel = chat.inputPanel
        let hadClock = panel.hasScheduledMessages
        panel.text = ""
        land(on: panel.scheduleButton, appear: !hadClock)
        showToast("Scheduled for " + ScheduleStop.phrase(for: date, now: Date()), in: chat)
    }

    private func dive(_ view: UIView, to end: CGPoint, completion: @escaping () -> Void) {
        let start = view.center
        let duration: CFTimeInterval = 0.5
        // A curve, not a slide: toward the clock's column first, then down into it. The bubble is right-aligned and
        // wide, so the curve stays left of the clock and the bubble shrinks early, or it would leave the screen.
        let control = CGPoint(x: end.x - 20, y: start.y + (end.y - start.y) * 0.2)
        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: end, controlPoint: control)

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path.cgPath
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.75, 1)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 0.06
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0, 0.55, 1)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.7, 1]
        fade.duration = duration
        view.layer.position = end
        view.layer.transform = CATransform3DMakeScale(0.06, 0.06, 1)
        view.layer.opacity = 0
        view.layer.add(move, forKey: "dive.position")
        view.layer.add(scale, forKey: "dive.scale")
        view.layer.add(fade, forKey: "dive.opacity")
        CATransaction.commit()
    }

    /// The clock appears as Telegram adds it; landing on it, it swells a little once (no spring, no rebound).
    private func land(on clock: UIButton, appear: Bool) {
        guard let panel = chat?.inputPanel else { return }
        if appear { panel.setHasScheduledMessages(true, animated: true) }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.15, 1]
        pulse.keyTimes = [0, 0.4, 1]
        pulse.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        pulse.duration = 0.35
        pulse.beginTime = CACurrentMediaTime() + (appear ? 0.12 : 0)
        pulse.fillMode = .backwards
        clock.imageView?.layer.add(pulse, forKey: "land")
    }

    private func showToast(_ text: String, in chat: ChatViewController) {
        toast?.removeFromSuperview()
        let glass = GlassView(tint: chat.theme.glassTint)
        glass.isUserInteractionEnabled = false
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = chat.theme.controlColor
        label.sizeToFit()
        let size = CGSize(width: label.bounds.width + 28, height: 34)
        glass.bounds = CGRect(origin: .zero, size: size)
        label.center = CGPoint(x: size.width / 2, y: size.height / 2)
        glass.contentView.addSubview(label)
        let panelTop = chat.overlayView.convert(chat.inputPanel.bounds, from: chat.inputPanel).minY
        glass.center = CGPoint(x: chat.overlayView.bounds.midX, y: panelTop - 14 - size.height / 2)
        glass.alpha = 0
        glass.transform = CGAffineTransform(translationX: 0, y: 8)
        chat.overlayView.addSubview(glass)
        toast = glass
        Motion.spring(0.35, delay: 0.1) {
            glass.alpha = 1
            glass.transform = .identity
        }
        UIView.animate(withDuration: 0.25, delay: 2.4, options: [.curveEaseIn]) {
            glass.alpha = 0
            glass.transform = CGAffineTransform(translationX: 0, y: 4)
        } completion: { _ in glass.removeFromSuperview() }
    }

    // MARK: Scenario (demo only)

    private func scenario(_ chat: ChatViewController) async {
        guard let window = chat.view.window else { return }
        let fingers = ScenarioFingers(window: window)
        try? await Task.sleep(for: .seconds(1.0))
        await play(typing: "Happy birthday!! 🎂 Have the best day", stops: [2], chat, fingers)
        try? await Task.sleep(for: .seconds(2.4))
        await play(typing: "Don't forget the tickets", stops: [-1, -2], chat, fingers)
    }

    /// Types `text`, holds Send (the options open), slides onto the ring and along it through `stops` (negative:
    /// from the end), lets go.
    private func play(typing text: String, stops path: [Int], _ chat: ChatViewController, _ fingers: ScenarioFingers) async {
        for i in text.indices {
            chat.inputPanel.text = String(text[...i])
            try? await Task.sleep(for: .seconds(0.035))
        }
        try? await Task.sleep(for: .seconds(0.5))
        let button = chat.inputPanel.sendButton
        let send = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        func move(_ p: CGPoint) {
            fingers.move(to: p)
            menu?.trackFinger(p)
            fingerMoved(p)
        }
        fingers.down(at: send)
        try? await Task.sleep(for: .seconds(0.32))
        chat.presentSendMenu()
        menuOpened()
        fingers.attach(to: menu?.window)
        // The screen as it is today, for a beat.
        try? await Task.sleep(for: .seconds(0.9))
        let count = ScheduleStop.stops(from: Date()).count
        let indices = path.map { $0 < 0 ? count + $0 : $0 }
        let radius = DialView.radius
        let a0 = DialView.startAngle
        func angle(_ index: Int) -> CGFloat {
            a0 + (DialView.endAngle - a0) * CGFloat(index) / CGFloat(max(1, count - 1))
        }
        func point(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
            CGPoint(x: send.x + r * cos(angle * .pi / 180), y: send.y - r * sin(angle * .pi / 180))
        }
        // Off Send up and to the left, onto the ring's start, then along it.
        await Self.run(duration: 0.35) { e in move(point(a0 - 10 + 10 * e, radius * e)) }
        try? await Task.sleep(for: .seconds(0.35))
        var current = 0
        for target in indices {
            let from = angle(current), to = angle(target)
            await Self.run(duration: 0.25 + 0.15 * Double(abs(target - current))) { e in move(point(from + (to - from) * e, radius)) }
            current = target
            try? await Task.sleep(for: .seconds(0.8))
        }
        fingers.up()
        fingerLifted()
    }

    /// Calls `step` with an eased 0…1 each frame for `duration` seconds.
    private static func run(duration: Double, _ step: @escaping (CGFloat) -> Void) async {
        let start = CACurrentMediaTime()
        while true {
            let t = min(1, (CACurrentMediaTime() - start) / duration)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            step(CGFloat(e))
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(8))
        }
    }
}
