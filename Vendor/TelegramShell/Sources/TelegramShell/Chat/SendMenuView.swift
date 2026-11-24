import UIKit

/// What holding Send opens in Telegram today: the screen blurs, the typed text turns into an outgoing bubble in place,
/// Send stays where it was, "Add an animated effect" sits above the bubble and the send options below it.
/// Source: submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift (CS), MessageItemView.swift,
/// SendButton.swift, ReactionSelectionNode/ReactionContextNode.swift, ContextControllerActionsStackNode.swift.
///
/// It lives in its own window above the keyboard (Telegram shows it over the keyboard too). Coordinates are the
/// screen's. A concept can put its own views into `featureContainer` (between the dim and the bubble), hide the
/// effects and the menu with `setOptionsHidden`, stop the finger from picking menu items with `tracksFinger`, and take
/// the preview bubble away with `dismiss(.handOff)`.
@MainActor
public final class SendMenuView: UIView {
    public enum Action { case send, sendSilently, schedule }
    public enum DismissStyle {
        /// Tap on the background: the bubble turns back into the field.
        case backToField
        /// Send or a menu item: the real field comes back at once, the preview fades where it is.
        case outToEmpty
        /// A concept takes the bubble (see `previewBubble`) and animates it itself; everything else fades.
        case handOff
    }

    public let text: String
    public let theme: Theme
    public var onAction: ((Action) -> Void)?
    /// Called once the screen is gone (the real field and Send are visible again by then).
    public var onDismissed: (() -> Void)?
    /// Whether the held finger highlights and picks menu items (CS:362-391). A concept that turns the gesture into
    /// something else switches this off.
    public var tracksFinger = true

    public let backgroundView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()
    public let featureContainer = PassthroughView()
    public let effectsPanel: EffectsPanelView
    public let previewBubble: SendPreviewBubble
    public let menuPanel: SendOptionsMenuView
    /// The copy of the field's Send capsule (CS:1166-1172; in the glass design the source's frame exactly).
    public let sendCopy = UIView()
    /// The arrow on `sendCopy` (a concept may swap it for its own glyph).
    public let sendIconView = UIImageView(image: Graphics.asset("TGSendIcon"))
    private let sendCopyButton = UIButton(type: .custom)

    /// Where the bubble starts (and returns to): the field's text, as a bubble without background.
    private let fieldBubbleFrame: CGRect
    /// The send capsule as it was in the panel.
    public let sourceSendFrame: CGRect
    /// Where the finger went down: the middle of Send before any shift.
    public var sourceSendCenter: CGPoint { CGPoint(x: sourceSendFrame.midX, y: sourceSendFrame.midY) }
    /// Laid out frames (after any shift up).
    public private(set) var bubbleFrame: CGRect = .zero
    private var shift: CGFloat = 0
    private var appearTime: CFTimeInterval = 0
    public private(set) var optionsHidden = false

    /// `editorFrame`: the field's text view, `sendFrame`: the visible Send capsule, both in screen coordinates.
    public init(frame: CGRect, text: String, theme: Theme, editorFrame: CGRect, sendFrame: CGRect, safeAreaInsets insets: UIEdgeInsets) {
        self.text = text
        self.theme = theme
        self.sourceSendFrame = sendFrame
        previewBubble = SendPreviewBubble(text: text, theme: theme)
        effectsPanel = EffectsPanelView(theme: theme)
        menuPanel = SendOptionsMenuView(theme: theme, items: [
            .init(action: .sendSilently, title: "Send Without Sound", icon: Graphics.asset("TGMenuSilentIcon")),
            .init(action: .schedule, title: "Schedule Message", icon: Graphics.asset("TGMenuScheduleIcon")),
        ])
        // MessageItemView starts as the editor's frame grown by the bubble's insets (CS:774-778, CS:842); here the
        // text keeps its place: the bubble's text inset (11 left, 6.33 top) sits on the editor's text.
        let textInset = (Metrics.inputHeight - Metrics.inputFont.lineHeight) / 2
        let startSize = previewBubble.size(maxTextWidth: editorFrame.width)
        fieldBubbleFrame = CGRect(x: editorFrame.minX - Metrics.textInsets.left,
                                  y: editorFrame.minY + textInset - Metrics.textInsets.top,
                                  width: startSize.width, height: startSize.height)
        super.init(frame: frame)

        backgroundView.frame = bounds
        addSubview(backgroundView)
        // contextMenu.dimColor: 000000 @0.6 dark, 000A26 @0.2 day (DefaultDark/DayPresentationTheme), blur on (CS:401-406).
        dimView.backgroundColor = theme.isDark ? UIColor(white: 0, alpha: 0.6) : UIColor(red: 0, green: 10 / 255, blue: 38 / 255, alpha: 0.2)
        dimView.frame = bounds
        addSubview(dimView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        dimView.addGestureRecognizer(tap)
        featureContainer.frame = bounds
        addSubview(featureContainer)
        addSubview(effectsPanel)
        addSubview(previewBubble)
        addSubview(menuPanel)
        menuPanel.onPick = { [weak self] action in self?.pick(action) }

        sendCopy.backgroundColor = theme.sendFill
        sendCopy.frame = sendFrame
        sendCopy.layer.cornerRadius = sendFrame.height / 2
        sendIconView.tintColor = theme.sendIcon
        sendIconView.contentMode = .center
        sendIconView.frame = sendCopy.bounds
        sendCopy.addSubview(sendIconView)
        addSubview(sendCopy)
        sendCopyButton.frame = sendFrame.insetBy(dx: -6, dy: -6)
        sendCopyButton.addAction(UIAction { [weak self] _ in self?.pick(.send) }, for: .touchUpInside)
        addSubview(sendCopyButton)

        layout(safeBottom: insets.bottom, maxTextWidth: editorFrame.width)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private var bubbleTarget: CGRect = .zero

    private func layout(safeBottom: CGFloat, maxTextWidth: CGFloat) {
        // Right edge on Send's left edge (the 40pt button right-aligned in the 46pt node: capsule.minX + 3),
        // bottom 6 above the node's bottom (capsule.maxY + 3 − 6) (CS:1179).
        let size = previewBubble.size(maxTextWidth: maxTextWidth)
        var bubble = CGRect(x: sourceSendFrame.minX + 3 - size.width, y: sourceSendFrame.maxY - 3 - size.height,
                            width: size.width, height: size.height)
        // Menu: right edge on the 40pt button's left edge + 1, 7 below the bubble (CS:340, CS:1196).
        let menuSize = menuPanel.sizeThatFits(.zero)
        var menu = CGRect(x: sourceSendFrame.minX + 3 + 1 - menuSize.width, y: bubble.maxY + 7, width: menuSize.width, height: menuSize.height)
        // Everything moves up when the menu would run below the safe area (CS:1206-1213).
        let limit = bounds.height - safeBottom - 8
        shift = max(0, menu.maxY - limit)
        bubble.origin.y -= shift
        menu.origin.y -= shift
        bubbleTarget = bubble
        bubbleFrame = bubble
        menuPanel.bounds = CGRect(origin: .zero, size: menu.size)
        // Grows from its top-right corner (CS:712).
        menuPanel.layer.anchorPoint = CGPoint(x: 1, y: 0)
        menuPanel.layer.position = CGPoint(x: menu.maxX, y: menu.minY)
        effectsPanel.layout(above: bubble, in: bounds)
    }

    // MARK: Appear / dismiss

    public func present() {
        appearTime = CACurrentMediaTime()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        previewBubble.frame = fieldBubbleFrame
        previewBubble.backgroundAlpha = 0
        previewBubble.layoutIfNeeded()
        dimView.alpha = 0
        sendCopy.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        menuPanel.alpha = 0
        menuPanel.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)

        // CS: appear is .spring(0.42) (the bezier); the menu's scale is a real spring, damping 104, stiffness 900,
        // mass 5 (CS:1292-1294).
        Motion.spring(0.42) {
            self.backgroundView.effect = UIBlurEffect(style: self.theme.isDark ? .dark : .light)
            self.dimView.alpha = 1
            self.previewBubble.frame = self.bubbleTarget
            self.previewBubble.backgroundAlpha = 1
            self.previewBubble.layoutIfNeeded()
            self.sendCopy.transform = CGAffineTransform(translationX: 0, y: -self.shift)
        }
        sendCopyButton.frame = sendCopyButton.frame.offsetBy(dx: 0, dy: -shift)
        UIView.animate(withDuration: 0.2) { self.menuPanel.alpha = 1 }
        let spring = UIViewPropertyAnimator(duration: 0.5, timingParameters: UISpringTimingParameters(mass: 5, stiffness: 900, damping: 104, initialVelocity: .zero))
        spring.addAnimations { self.menuPanel.transform = .identity }
        spring.startAnimation()
        effectsPanel.animateIn()
    }

    public func dismiss(_ style: DismissStyle) {
        isUserInteractionEnabled = false
        let finish = { [weak self] in
            guard let self else { return }
            self.onDismissed?()
        }
        switch style {
        case .backToField:
            // CS:1254-1267: the bubble morphs back into the field, Send returns to its place.
            Motion.spring(0.4) {
                self.backgroundView.effect = nil
                self.dimView.alpha = 0
                self.previewBubble.frame = self.fieldBubbleFrame
                self.previewBubble.backgroundAlpha = 0
                self.previewBubble.layoutIfNeeded()
                self.sendCopy.transform = .identity
                self.menuPanel.alpha = 0
                self.menuPanel.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
                self.effectsPanel.alpha = 0
                self.featureContainer.alpha = 0
            } completion: { _ in finish() }
        case .outToEmpty, .handOff:
            // CS:1430-1439: the real field is back at once; the preview and Send fade where they are.
            onRestoreField?()
            onRestoreField = nil
            Motion.spring(0.4) {
                self.backgroundView.effect = nil
                self.dimView.alpha = 0
                if style == .outToEmpty { self.previewBubble.alpha = 0 }
                self.sendCopy.alpha = 0
                self.menuPanel.alpha = 0
                self.menuPanel.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
                self.effectsPanel.alpha = 0
                self.featureContainer.alpha = 0
            } completion: { _ in finish() }
        }
    }

    /// Set by the chat: shows the real field text and Send again.
    var onRestoreField: (() -> Void)?

    /// Hides the effects and the menu. Hidden, Send goes back under the finger (the shift up was only for the menu);
    /// shown again, Send and the bubble return to their menu places.
    public func setOptionsHidden(_ hidden: Bool, animated: Bool) {
        guard hidden != optionsHidden else { return }
        optionsHidden = hidden
        menuPanel.highlight(nil)
        let sendShift = hidden ? 0 : -shift
        sendCopyButton.frame = sourceSendFrame.insetBy(dx: -6, dy: -6).offsetBy(dx: 0, dy: sendShift)
        let apply = {
            self.menuPanel.alpha = hidden ? 0 : 1
            self.menuPanel.transform = hidden ? CGAffineTransform(scaleX: 0.6, y: 0.6) : .identity
            self.effectsPanel.alpha = hidden ? 0 : 1
            self.effectsPanel.transform = hidden ? CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.96, y: 0.96) : .identity
            self.sendCopy.transform = CGAffineTransform(translationX: 0, y: sendShift)
            if !hidden {
                self.previewBubble.frame = self.bubbleTarget
                self.previewBubble.layoutIfNeeded()
            }
        }
        if animated { Motion.spring(0.3, apply) } else { apply() }
    }

    // MARK: Finger and taps

    /// Picks only once the screen has been in for 0.35 s (CS:366, CS:381).
    private var fingerReady: Bool { CACurrentMediaTime() - appearTime > 0.35 }

    public func trackFinger(_ point: CGPoint) {
        guard tracksFinger, !optionsHidden, fingerReady else { menuPanel.highlight(nil); return }
        menuPanel.highlight(menuPanel.item(at: convert(point, to: menuPanel)))
    }

    /// Returns whether the release picked something.
    @discardableResult
    public func releaseFinger(_ point: CGPoint) -> Bool {
        defer { menuPanel.highlight(nil) }
        guard tracksFinger, !optionsHidden, fingerReady, let action = menuPanel.item(at: convert(point, to: menuPanel)) else { return false }
        pick(action)
        return true
    }

    private func pick(_ action: Action) {
        onAction?(action)
    }

    @objc private func backgroundTapped() {
        dismiss(.backToField)
    }
}

// MARK: - Preview bubble

/// The outgoing bubble the text turns into: text only, no time (MessageItemView). A concept can add a trailing view
/// (a time, say) with `setTrailing`.
@MainActor
public final class SendPreviewBubble: UIView {
    public let background = BubbleBackgroundView(incoming: false, position: .single)
    public let label = UILabel()
    public private(set) var trailing: UIView?
    private var trailingSize: CGSize = .zero
    public var backgroundAlpha: CGFloat {
        get { background.alpha }
        set { background.alpha = newValue }
    }

    init(text: String, theme: Theme) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(background)
        background.apply(theme.outgoing)
        label.text = text
        label.font = Metrics.messageFont
        label.textColor = theme.outgoing.text
        label.numberOfLines = 0
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var maxTextWidth: CGFloat = 0

    /// The bubble for text wrapped at `maxTextWidth` (the field's width), with the tail column.
    public func size(maxTextWidth: CGFloat) -> CGSize {
        self.maxTextWidth = maxTextWidth
        let insets = Metrics.textInsets
        let text = label.sizeThatFits(CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
        let trailingWidth = trailing == nil ? 0 : trailingSize.width + 6
        let width = ceil(text.width) + trailingWidth + insets.left + insets.right + Metrics.tailWidth
        let height = max(Metrics.minBubbleSize.height, ceil(text.height) + insets.top + insets.bottom)
        return CGSize(width: width, height: height)
    }

    /// Adds (or removes) a view after the text, on its last line. Returns the new size; the caller animates the frame.
    @discardableResult
    public func setTrailing(_ view: UIView?, size: CGSize) -> CGSize {
        trailing?.removeFromSuperview()
        trailing = view
        trailingSize = size
        if let view { addSubview(view) }
        setNeedsLayout()
        return self.size(maxTextWidth: maxTextWidth)
    }

    private var hasViewport = false

    public override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        // Night's outgoing gradient is screen-space, as in the chat (MessageView); set where the bubble first
        // appears and then kept, so it doesn't jump while the bubble moves.
        if !hasViewport, let window {
            hasViewport = true
            background.setGradientViewport(background.convert(window.bounds, from: window))
        }
        let insets = Metrics.textInsets
        let trailingWidth = trailing == nil ? 0 : trailingSize.width + 6
        let textWidth = max(1, bounds.width - insets.left - insets.right - Metrics.tailWidth - trailingWidth)
        let textHeight = label.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        label.frame = CGRect(x: insets.left, y: insets.top, width: textWidth, height: ceil(textHeight))
        if let trailing {
            trailing.frame = CGRect(x: label.frame.maxX + 6, y: bounds.height - insets.bottom - trailingSize.height,
                                    width: trailingSize.width, height: trailingSize.height)
        }
    }
}

// MARK: - Effects panel

/// "Add an animated effect": a glass panel with a row of effects above the bubble.
/// ReactionContextNode.swift: title 13pt (:199), row 46 high, 36pt items 8 apart, 6pt side inset, up to 8 per row with
/// the expand button (:977, :1332-1354); bottom 7 above the bubble, x = bubble.minX − 26 kept 11 from the edges
/// (:919-940). Appears with alpha over 0.15 and each item scaling 0.01 → 1 over 0.4, staggered (:2522-2576).
@MainActor
public final class EffectsPanelView: UIView {
    private let glass = GlassView()
    private let title = UILabel()
    private var items: [UIView] = []
    private let expand = UIImageView()
    private let bigDot = GlassView()
    private let smallDot = GlassView()
    static let effects = ["👍", "👎", "❤️", "🔥", "🎉", "💩", "🥰"]

    init(theme: Theme) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        for dot in [bigDot, smallDot] {
            dot.tint = theme.glassTint
            addSubview(dot)
        }
        glass.tint = theme.glassTint
        glass.cornerRadius = 23
        addSubview(glass)
        title.text = "Add an animated effect"
        title.font = .systemFont(ofSize: 13)
        title.textColor = theme.controlColor.withAlphaComponent(0.5)
        title.textAlignment = .center
        glass.contentView.addSubview(title)
        for effect in Self.effects {
            let label = UILabel()
            label.text = effect
            label.font = .systemFont(ofSize: 29)
            label.textAlignment = .center
            glass.contentView.addSubview(label)
            items.append(label)
        }
        expand.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        expand.tintColor = theme.controlColor.withAlphaComponent(0.6)
        expand.contentMode = .center
        expand.backgroundColor = theme.controlColor.withAlphaComponent(0.08)
        expand.layer.cornerRadius = 15
        glass.contentView.addSubview(expand)
        items.append(expand)
    }

    required init?(coder: NSCoder) { fatalError() }

    func layout(above bubble: CGRect, in bounds: CGRect) {
        let item: CGFloat = 36, spacing: CGFloat = 8, side: CGFloat = 6, rowHeight: CGFloat = 46
        let titleHeight = 6 + ceil(title.font.lineHeight)
        let width = side * 2 + item * CGFloat(items.count) + spacing * CGFloat(items.count - 1)
        let height = titleHeight + rowHeight
        var x = bubble.minX - 26
        x = min(max(x, 11), bounds.width - 11 - width)
        let panel = CGRect(x: x, y: bubble.minY - 7 - height, width: width, height: height)
        frame = bounds
        glass.frame = panel
        title.frame = CGRect(x: 0, y: 6, width: width, height: ceil(title.font.lineHeight))
        for (i, view) in items.enumerated() {
            let box = CGRect(x: side + CGFloat(i) * (item + spacing), y: titleHeight + (rowHeight - item) / 2, width: item, height: item)
            if view === expand {
                view.frame = box.insetBy(dx: 3, dy: 3)
            } else {
                view.frame = box.insetBy(dx: -4, dy: -4)
            }
        }
        // The two "thought" dots between the panel and the bubble.
        bigDot.frame = CGRect(x: bubble.minX - 5 - 6, y: panel.maxY - 3, width: 12, height: 12)
        smallDot.frame = CGRect(x: bubble.minX - 13 - 3, y: panel.maxY + 10, width: 6, height: 6)
    }

    func animateIn() {
        alpha = 0
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
        for (i, view) in items.enumerated() {
            view.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            // Staggered from the item nearest the bubble's corner (the right end) outwards.
            let delay = 0.01 + 0.025 * Double(items.count - 1 - i)
            Motion.spring(0.4, delay: delay) { view.transform = .identity }
        }
    }
}

// MARK: - Options menu

/// The context menu under the bubble. ContextControllerActionsStackNode.swift: 220…240 wide (:2059), rows with an
/// 18pt side inset and 11pt vertical inset, icon in a 32pt slot at x 20, title at x 60 (:213-218, :588), 10pt above and
/// below the list (:996-1020), glass with radius min(30, h/2) (:1580); the highlight is inset 10 at the sides, radius
/// min(20, h/2), white @0.1 in dark, black @0.1 in day (:1118-1137).
@MainActor
public final class SendOptionsMenuView: UIView {
    public struct Item {
        public let action: SendMenuView.Action
        public let title: String
        public let icon: UIImage?
    }

    private let glass = GlassView()
    private let highlightView = UIView()
    private var rows: [(item: Item, frame: CGRect, view: UIView)] = []
    var onPick: ((SendMenuView.Action) -> Void)?
    static let rowHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 10

    init(theme: Theme, items: [Item]) {
        super.init(frame: .zero)
        glass.tint = theme.glassTint
        addSubview(glass)
        highlightView.backgroundColor = theme.isDark ? UIColor(white: 1, alpha: 0.1) : UIColor(white: 0, alpha: 0.1)
        highlightView.alpha = 0
        glass.contentView.addSubview(highlightView)
        for item in items {
            let row = UIView()
            let icon = UIImageView(image: item.icon?.withRenderingMode(.alwaysTemplate))
            icon.tintColor = theme.controlColor
            icon.contentMode = .center
            icon.frame = CGRect(x: 20, y: 0, width: 32, height: Self.rowHeight)
            row.addSubview(icon)
            let label = UILabel()
            label.text = item.title
            label.font = .systemFont(ofSize: 17)
            label.textColor = theme.controlColor
            label.sizeToFit()
            label.frame = CGRect(x: 60, y: (Self.rowHeight - label.bounds.height) / 2, width: label.bounds.width, height: label.bounds.height)
            row.addSubview(label)
            let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
            row.addGestureRecognizer(tap)
            glass.contentView.addSubview(row)
            rows.append((item, .zero, row))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let titles = rows.compactMap { ($0.view.subviews.last as? UILabel)?.bounds.width }.max() ?? 0
        let width = min(240, max(220, 60 + titles + 18))
        return CGSize(width: width, height: Self.verticalPadding * 2 + Self.rowHeight * CGFloat(rows.count))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        glass.cornerRadius = min(30, bounds.height / 2)
        for i in rows.indices {
            let frame = CGRect(x: 0, y: Self.verticalPadding + CGFloat(i) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
            rows[i].frame = frame
            rows[i].view.frame = frame
        }
    }

    func item(at point: CGPoint) -> SendMenuView.Action? {
        guard bounds.contains(point) else { return nil }
        return rows.first { $0.frame.contains(point) }?.item.action
    }

    func highlight(_ action: SendMenuView.Action?) {
        guard let row = rows.first(where: { $0.item.action == action }) else {
            highlightView.alpha = 0
            return
        }
        let frame = row.frame.insetBy(dx: 10, dy: 0)
        if highlightView.alpha == 0 { UISelectionFeedbackGenerator().selectionChanged() }
        highlightView.frame = frame
        highlightView.layer.cornerRadius = min(20, frame.height / 2)
        highlightView.alpha = 1
    }

    @objc private func rowTapped(_ tap: UITapGestureRecognizer) {
        guard let row = rows.first(where: { $0.view === tap.view }) else { return }
        highlight(row.item.action)
        onPick?(row.item.action)
    }
}
