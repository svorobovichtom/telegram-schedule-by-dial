import UIKit

/// Telegram's chat screen in plain UIKit. Messages are plain views in a scroll view (no cell reuse),
/// so a concept can grab, snapshot, move or animate any bubble directly.
public final class ChatViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    public private(set) var chat: DemoChat
    public private(set) var theme: Theme = .dayClassic

    public let wallpaperView: WallpaperView
    public let scrollView = UIScrollView()
    /// Messages live here; it is the scroll view's content.
    public let contentView = UIView()
    /// Telegram's edge effect: the wallpaper over the content under the header and under the input panel.
    public let topEdgeView: WallpaperEdgeView
    public let bottomEdgeView: WallpaperEdgeView

    /// The shape of a wallpaper edge effect: where it is, how long its fade is, how much it covers.
    public struct EdgeShape {
        public var frame: CGRect
        public var fade: CGFloat
        public var alpha: CGFloat

        public init(frame: CGRect, fade: CGFloat, alpha: CGFloat) {
            self.frame = frame
            self.fade = fade
            self.alpha = alpha
        }
    }
    /// A feature that changes what sits at the screen's edges (hides the input panel, floats something under the
    /// header) can reshape the edge effects. Applied at once and on every layout; nil restores the chat's own.
    public var topEdgeOverride: EdgeShape? {
        didSet { if let shape = topEdgeOverride { topEdgeView.update(frame: shape.frame, screen: view.bounds, edgeSize: shape.fade, alpha: shape.alpha) } else { view.setNeedsLayout() } }
    }
    public var bottomEdgeOverride: EdgeShape? {
        didSet { if let shape = bottomEdgeOverride { bottomEdgeView.update(frame: shape.frame, screen: view.bounds, edgeSize: shape.fade, alpha: shape.alpha) } else { view.setNeedsLayout() } }
    }
    public let headerView: ChatHeaderView
    public let inputPanel = InputPanelView()
    /// The round "scroll to the latest messages" button over the input panel's right edge
    /// (ChatHistoryNavigationButtonNode.swift, ChatHistoryNavigationButtons.swift).
    public let downButton = GlassButton(icon: ChatViewController.downChevron)
    /// A feature that hides the chat (zooms out of it) turns the button off here.
    public var downButtonSuppressed = false { didSet { updateDownButton(animated: true) } }
    private var downButtonShown = false
    /// Above everything (header and input included). Put overlays of a concept here.
    public let overlayView = PassthroughView()

    /// Holding Send: Telegram's ContextGesture fires 0.12 + 0.2 s after touch-down (Display/Source/ContextGesture.swift:77,
    /// :153-176) and opens the send options (SendMenuView). A concept can add its own target to follow the finger.
    public let sendMenuGesture = UILongPressGestureRecognizer()
    public private(set) var sendMenu: SendMenuView?
    private var sendMenuWindow: UIWindow?
    /// Scheduling a message (from the send options or a concept). nil: the field clears and the scheduled-messages
    /// clock appears (Telegram then also opens the scheduled messages, which this shell doesn't have).
    public var onScheduleMessage: ((String, Date) -> Void)?

    public private(set) var messageViews: [MessageView] = []
    public private(set) var dateHeaderViews: [DateHeaderView] = []

    private let features: [ChatFeature]
    private var didInstallFeatures = false
    private let keyboardTracker = UIView()

    public init(chat: DemoChat, features: [ChatFeature] = []) {
        self.chat = chat
        self.features = features
        wallpaperView = WallpaperView(theme: Theme.dayClassic.wallpaper)
        headerView = ChatHeaderView(peer: chat.peer)
        topEdgeView = WallpaperEdgeView(edge: .top, theme: Theme.dayClassic.wallpaper)
        bottomEdgeView = WallpaperEdgeView(edge: .bottom, theme: Theme.dayClassic.wallpaper)
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(wallpaperView)
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = true
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)
        view.addSubview(topEdgeView)
        view.addSubview(bottomEdgeView)
        view.addSubview(headerView)
        view.addSubview(inputPanel)
        view.addSubview(downButton)
        view.addSubview(overlayView)
        downButton.alpha = 0
        downButton.isHidden = true
        downButton.addAction(UIAction { [weak self] _ in self?.scrollToBottom(animated: true) }, for: .touchUpInside)

        // A zero-size view pinned to the keyboard guide: makes UIKit run layout inside the keyboard animation.
        keyboardTracker.isHidden = true
        keyboardTracker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardTracker)
        NSLayoutConstraint.activate([
            keyboardTracker.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            keyboardTracker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardTracker.widthAnchor.constraint(equalToConstant: 1),
            keyboardTracker.heightAnchor.constraint(equalToConstant: 1),
        ])

        headerView.onBack = { [weak self] in self?.navigationController?.popViewController(animated: true) }
        inputPanel.onSend = { [weak self] text in self?.send(text: text) }
        sendMenuGesture.minimumPressDuration = 0.32
        sendMenuGesture.addTarget(self, action: #selector(handleSendMenuGesture(_:)))
        inputPanel.sendButton.addGestureRecognizer(sendMenuGesture)
        inputPanel.onHeightChange = { [weak self] in
            UIView.animate(springDuration: 0.3, bounce: 0) { self?.view.setNeedsLayout(); self?.view.layoutIfNeeded() }
        }

        for message in chat.messages { messageViews.append(MessageView(message: message, position: .single, theme: theme)) }
        applyTheme()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.applyTheme()
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = self
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.contains(self) != true {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }

    private var lastLayoutWidth: CGFloat = 0

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        wallpaperView.frame = bounds
        overlayView.frame = bounds
        scrollView.frame = bounds

        let headerHeight = view.safeAreaInsets.top + ChatHeaderView.barHeight
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)

        // Before the keyboard layout guide has resolved (the first passes at launch) the tracker sits at the top:
        // that is not a keyboard. Without this the input panel starts above the screen and the bottom edge effect,
        // which hangs off it, covers the whole chat for a few frames.
        let keyboardTop = keyboardTracker.frame.maxY > bounds.height / 4 ? keyboardTracker.frame.maxY : bounds.height
        let restingBottom = bounds.height - view.safeAreaInsets.bottom
        let panelBottom = min(restingBottom, keyboardTop) - Metrics.inputBottomGap
        let panelHeight = inputPanel.panelHeight
        inputPanel.frame = CGRect(x: 0, y: panelBottom - panelHeight, width: bounds.width, height: panelHeight)

        // ChatControllerNode: top down to the list's top inset + 34 (at least 100 tall), 80pt fade;
        // bottom from 20 above the input panel to the screen bottom (at least 100 tall), 60pt fade.
        // ChatControllerNode: 40pt, 8 from the right edge, 20 above the input panels.
        let downSize: CGFloat = 40
        downButton.bounds = CGRect(x: 0, y: 0, width: downSize, height: downSize)
        downButton.center = CGPoint(x: bounds.width - view.safeAreaInsets.right - 8 - downSize / 2,
                                    y: inputPanel.frame.minY - 20 - downSize / 2)

        let topExtent = headerHeight + 34
        let topHeight = max(100, topExtent)
        // edgeEffectAlpha: 0.85 over a single-color wallpaper, 0.75 otherwise.
        let edgeAlpha: CGFloat = theme.wallpaper.plainColor != nil ? 0.85 : 0.75
        let top = topEdgeOverride ?? EdgeShape(frame: CGRect(x: 0, y: topExtent - topHeight, width: bounds.width, height: topHeight),
                                               fade: 80, alpha: edgeAlpha)
        topEdgeView.update(frame: top.frame, screen: bounds, edgeSize: top.fade, alpha: top.alpha)
        let bottomTop = inputPanel.frame.minY - 20
        let bottom = bottomEdgeOverride ?? EdgeShape(frame: CGRect(x: 0, y: bottomTop, width: bounds.width, height: max(100, bounds.height - bottomTop)),
                                                     fade: 60, alpha: edgeAlpha)
        bottomEdgeView.update(frame: bottom.frame, screen: bounds, edgeSize: bottom.fade, alpha: bottom.alpha)

        let wasAtBottom = isAtBottom
        if lastLayoutWidth != bounds.width {
            lastLayoutWidth = bounds.width
            layoutMessages()
            updateInsets()
            scrollToBottom(animated: false)
        } else {
            updateInsets()
            if wasAtBottom { scrollToBottom(animated: false) }
        }
        updateScrollDependentViews()

        if !didInstallFeatures {
            didInstallFeatures = true
            features.forEach { $0.chatDidLoad(self) }
        }
    }

    // MARK: Theme

    private func applyTheme() {
        theme = Theme.current(for: traitCollection)
        wallpaperView.setTheme(theme.wallpaper)
        wallpaperView.layoutIfNeeded()
        for edge in [topEdgeView, bottomEdgeView] {
            edge.wallpaper.setTheme(theme.wallpaper)
            edge.wallpaper.layoutIfNeeded()
        }
        headerView.apply(theme)
        inputPanel.apply(theme)
        downButton.glass.tint = theme.glassTint
        downButton.iconView.tintColor = theme.controlColor
        messageViews.forEach { $0.apply(theme) }
        // Text is drawn with its color baked in: relayout re-renders it and rebuilds the date pills.
        layoutMessages()
        updateScrollDependentViews()
        view.setNeedsLayout()
    }

    // MARK: Layout

    private func sameGroup(_ a: DemoMessage, _ b: DemoMessage) -> Bool {
        a.isOutgoing == b.isOutgoing && a.author == b.author
            && Calendar.current.isDate(a.date, inSameDayAs: b.date)
            && abs(a.date.timeIntervalSince(b.date)) < 10 * 60
    }

    private func position(at i: Int, in messages: [DemoMessage]) -> BubblePosition {
        let prev = i > 0 && sameGroup(messages[i - 1], messages[i])
        let next = i < messages.count - 1 && sameGroup(messages[i], messages[i + 1])
        switch (prev, next) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

    public static func dateTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }

    /// Lays out all bubbles and date headers top to bottom. Call after changing messages yourself.
    public func layoutMessages() {
        let width = view.bounds.width
        guard width > 0 else { return }
        dateHeaderViews.forEach { $0.removeFromSuperview() }
        dateHeaderViews = []

        var y: CGFloat = 0
        var previous: DemoMessage?
        let messages = messageViews.map(\.message)
        for (i, messageView) in messageViews.enumerated() {
            let message = messageView.message
            if previous == nil || !Calendar.current.isDate(previous!.date, inSameDayAs: message.date) {
                let header = DateHeaderView(text: Self.dateTitle(message.date))
                header.apply(theme, wallpaper: wallpaperView)
                header.frame = CGRect(x: 0, y: y, width: width, height: Metrics.dateHeaderHeight)
                contentView.insertSubview(header, at: 0)
                dateHeaderViews.append(header)
                y += Metrics.dateHeaderHeight
            } else if let previous {
                y += sameGroup(previous, message) ? Metrics.mergedSpacing : Metrics.groupSpacing
            }
            messageView.update(position: position(at: i, in: messages))
            if messageView.superview == nil { contentView.addSubview(messageView) }
            let layout = MessageView.layout(message: message, width: width, safeInsets: view.safeAreaInsets,
                                            plainWallpaper: theme.wallpaper.plainColor != nil)
            messageView.bounds = CGRect(x: 0, y: 0, width: width, height: layout.height)
            messageView.center = CGPoint(x: width / 2, y: y + layout.height / 2)
            messageView.apply(layout, width: width)
            y += layout.height
            previous = message
        }
        y += Metrics.groupSpacing
        contentView.frame = CGRect(x: 0, y: 0, width: width, height: y)
        scrollView.contentSize = CGSize(width: width, height: y)
        // Frames moved: which views are near the screen has to be worked out again (a relayout that doesn't end
        // in a scroll, like a theme change at launch, would otherwise leave everything hidden).
        updateScrollDependentViews()
    }

    private func updateInsets() {
        let top = headerView.frame.maxY + 4
        let bottom = view.bounds.height - inputPanel.frame.minY + 6
        let visible = view.bounds.height - top - bottom
        // Short chats stick to the bottom, like Telegram's inverted list.
        let extra = max(0, visible - scrollView.contentSize.height)
        scrollView.contentInset = UIEdgeInsets(top: top + extra, left: 0, bottom: bottom, right: 0)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
    }

    public var isAtBottom: Bool {
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        return scrollView.contentOffset.y >= maxOffset - 2
    }

    public func scrollToBottom(animated: Bool) {
        let offset = max(-scrollView.contentInset.top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
        if animated {
            // From further than a screen away the latest messages come in from just below the current screen, not
            // past everything in between (Telegram-iOS/submodules/Display/Source/ListView.swift, scrollToItem with
            // directionHint .Down: offset = updatedUpperBound - previousLowerBound).
            let travel = scrollView.bounds.height
            if offset - scrollView.contentOffset.y > travel { scrollView.contentOffset.y = offset - travel }
            // The scroll view's own animation: it reports every frame, so the messages on the way get shown.
            scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: true)
        } else {
            scrollView.contentOffset.y = offset
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateScrollDependentViews()
        updateDownButton(animated: true)
    }

    /// Shown once the latest messages are scrolled more than a few lines away; fades and scales in with a spring.
    private func updateDownButton(animated: Bool) {
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        let show = !downButtonSuppressed && scrollView.contentOffset.y < maxOffset - 80
        guard show != downButtonShown else { return }
        downButtonShown = show
        if show { downButton.isHidden = false }
        let apply = {
            self.downButton.alpha = show ? 1 : 0
            self.downButton.transform = show ? .identity : CGAffineTransform(scaleX: 0.2, y: 0.2)
        }
        if animated {
            UIView.animate(springDuration: 0.3, bounce: 0, animations: apply) { _ in
                if !self.downButtonShown { self.downButton.isHidden = true }
            }
        } else {
            apply()
            downButton.isHidden = !show
        }
    }

    /// PresentationResourcesChat.chatHistoryNavigationButtonImage: a 1.5pt chevron in 38 × 38.
    static let downChevron: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 38, height: 38)).image { context in
        let c = context.cgContext
        c.setStrokeColor(UIColor.white.cgColor)
        c.setLineWidth(1.5)
        // Drawn there in a bottom-left origin context, at y 22 → 13 → 22.
        c.move(to: CGPoint(x: 9.5, y: 16))
        c.addLine(to: CGPoint(x: 18.5, y: 25))
        c.addLine(to: CGPoint(x: 27.5, y: 16))
        c.strokePath()
    }.withRenderingMode(.alwaysTemplate)

    private func updateScrollDependentViews() {
        // Views more than a screen away stay hidden, so Core Animation doesn't draw them (Telegram's list keeps only
        // visible nodes; with hundreds of messages drawing everything makes the first frame take seconds).
        // Frames stay valid, so features can still measure them.
        let height = max(scrollView.bounds.height, 1)
        let alive = CGRect(x: 0, y: scrollView.contentOffset.y - height, width: view.bounds.width, height: height * 3)
        for messageView in messageViews where messageView.transform.isIdentity {
            messageView.isHidden = !messageView.frame.intersects(alive)
        }
        for header in dateHeaderViews { header.isHidden = !header.frame.intersects(alive) }
        dateHeaderViews.forEach { $0.updatePortal(wallpaper: wallpaperView) }
        if theme.outgoing.fill.count > 1 {
            messageViews.lazy.filter(\.message.isOutgoing).forEach { $0.updateScreenGradient() }
        }
    }

    // MARK: Messages API

    public func messageView(for id: UUID) -> MessageView? {
        messageViews.first { $0.message.id == id }
    }

    /// A bubble laid out exactly as this chat would show it, but not in the chat: for a concept that animates a
    /// message somewhere else (a scheduled message that flies away instead of landing in the list).
    /// Its frame is chat-width and positioned at the origin; `bubbleFrame` is where the bubble sits inside it.
    public func detachedMessageView(for message: DemoMessage) -> MessageView {
        let width = view.bounds.width
        let messageView = MessageView(message: message, position: .single, theme: theme)
        let layout = MessageView.layout(message: message, width: width, safeInsets: view.safeAreaInsets,
                                        plainWallpaper: theme.wallpaper.plainColor != nil)
        messageView.frame = CGRect(x: 0, y: 0, width: width, height: layout.height)
        messageView.apply(layout, width: width)
        return messageView
    }

    /// Appends a message at the bottom. `animated`: the chat scrolls up and the bubble slides in from the input field.
    @discardableResult
    public func insert(_ message: DemoMessage, animated: Bool) -> MessageView {
        chat.messages.append(message)
        let messageView = MessageView(message: message, position: .single, theme: theme)
        messageViews.append(messageView)
        if !animated {
            layoutMessages(); updateInsets(); scrollToBottom(animated: false)
            return messageView
        }
        layoutMessages()
        updateInsets()
        let field = view.convert(inputPanel.fieldView.frame, from: inputPanel)
        let target = view.convert(messageView.bubbleFrame, from: messageView)
        let targetOffset = max(-scrollView.contentInset.top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
        // `target` is at the current offset; the scroll and the transform animate together, so at t = 0 the bubble's
        // bottom sits on the field's bottom (behind its glass), as if the typed text became the bubble.
        // Incoming: rises a little from below while fading in.
        let startY = message.isOutgoing ? field.maxY - target.maxY : 20
        messageView.transform = CGAffineTransform(translationX: 0, y: startY)
        messageView.alpha = message.isOutgoing ? 1 : 0
        UIView.animate(springDuration: 0.42, bounce: 0.08) {
            self.scrollView.contentOffset.y = targetOffset
            messageView.transform = .identity
            messageView.alpha = 1
        }
        return messageView
    }

    public func remove(_ id: UUID, animated: Bool) {
        guard let index = messageViews.firstIndex(where: { $0.message.id == id }) else { return }
        let messageView = messageViews.remove(at: index)
        chat.messages.removeAll { $0.id == id }
        let apply = { self.layoutMessages(); self.updateInsets() }
        if animated {
            UIView.animate(springDuration: 0.35, bounce: 0) {
                messageView.alpha = 0
                apply()
            } completion: { _ in messageView.removeFromSuperview() }
        } else {
            messageView.removeFromSuperview()
            apply()
        }
    }

    /// What Send does by default: an outgoing message, the wallpaper turns one phase, checks go read after a moment.
    public func send(text: String) {
        let message = DemoMessage(text: text, isOutgoing: true, date: Date(), status: .sent)
        let messageView = insert(message, animated: true)
        wallpaperView.animatePhase()
        topEdgeView.wallpaper.animatePhase()
        bottomEdgeView.wallpaper.animatePhase()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            messageView.update(status: .read)
            self.layoutMessages()
        }
    }

    // MARK: Send options

    @objc private func handleSendMenuGesture(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: nil)
        switch gesture.state {
        case .began: presentSendMenu()
        case .changed: sendMenu?.trackFinger(point)
        case .ended: sendMenu?.releaseFinger(point)
        default: break
        }
    }

    /// Opens the send options over everything (keyboard included), as holding Send does.
    public func presentSendMenu() {
        let text = inputPanel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sendMenu == nil, !text.isEmpty, let scene = view.window?.windowScene else { return }
        let window = UIWindow(windowScene: scene)
        // Above the keyboard's window.
        window.windowLevel = UIWindow.Level(rawValue: 10_000_001)
        window.overrideUserInterfaceStyle = view.window?.overrideUserInterfaceStyle ?? .unspecified
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false

        let textView = inputPanel.textView
        let editor = textView.convert(textView.bounds, to: nil)
        let send = inputPanel.convert(inputPanel.sendCapsuleFrame, to: nil)
        let menu = SendMenuView(frame: window.bounds, text: text, theme: theme, editorFrame: editor, sendFrame: send,
                                safeAreaInsets: view.window?.safeAreaInsets ?? .zero)
        root.view.addSubview(menu)
        // The real text and Send hide under their copies (CS:1412-1422).
        textView.alpha = 0
        inputPanel.sendCapsule.alpha = 0
        let restore = { [weak self] in
            self?.inputPanel.textView.alpha = 1
            self?.inputPanel.sendCapsule.alpha = 1
        }
        menu.onRestoreField = restore
        menu.onDismissed = { [weak self, weak window] in
            restore()
            window?.isHidden = true
            self?.sendMenuWindow = nil
            self?.sendMenu = nil
        }
        menu.onAction = { [weak self, weak menu] action in
            guard let self, let menu else { return }
            menu.dismiss(.outToEmpty)
            switch action {
            case .send, .sendSilently:
                self.inputPanel.text = ""
                self.send(text: text)
            case .schedule:
                self.presentScheduleTimePicker { date in
                    if let date { self.scheduleMessage(text, at: date) }
                }
            }
        }
        sendMenuWindow = window
        sendMenu = menu
        menu.present()
    }

    /// Telegram's schedule sheet. `completion` gets the picked moment, or nil if it was closed.
    public func presentScheduleTimePicker(initial: Date = Date().addingTimeInterval(10 * 60), completion: @escaping (Date?) -> Void) {
        present(ScheduleTimeSheet(theme: theme, initial: initial, completion: completion), animated: true)
    }

    /// Schedules `text` (see `onScheduleMessage`).
    public func scheduleMessage(_ text: String, at date: Date) {
        if let onScheduleMessage {
            onScheduleMessage(text, date)
        } else {
            inputPanel.text = ""
            inputPanel.setHasScheduledMessages(true, animated: true)
        }
    }

    /// An incoming message after a delay, as if the other side replied.
    public func receive(_ text: String, after delay: TimeInterval = 1, author: String? = nil) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            self.insert(DemoMessage(text: text, isOutgoing: false, date: Date(), author: author), animated: true)
        }
    }
}

/// A view that lets touches through except on its subviews.
public final class PassthroughView: UIView {
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains { !$0.isHidden && $0.alpha > 0.01 && $0.isUserInteractionEnabled && $0.frame.contains(point) }
    }
}
