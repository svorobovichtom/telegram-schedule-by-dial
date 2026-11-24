import UIKit

// MARK: - Date header

/// "Today" pill: 22pt capsule, 13pt medium white text over the wallpaper gradient at saturation 1.7 + black 0.2.
/// Source: submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift
public final class DateHeaderView: UIView {
    public let label = UILabel()
    private let pill = UIView()
    private let portalView = UIImageView()
    private let dimView = UIView()

    public init(text: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        pill.clipsToBounds = true
        addSubview(pill)
        portalView.contentMode = .scaleToFill
        pill.addSubview(portalView)
        pill.addSubview(dimView)
        label.font = Metrics.datePillFont
        label.text = text
        label.textAlignment = .center
        pill.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ theme: Theme, wallpaper: WallpaperView) {
        label.textColor = theme.serviceText
        dimView.backgroundColor = theme.serviceDim
        portalView.image = wallpaper.dimmedGradientImage
        if theme.wallpaper.intensity < 0 {
            portalView.image = nil
            pill.backgroundColor = UIColor(rgb: 0x1f1f1f) // Night service fill
        } else {
            pill.backgroundColor = .clear
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let textWidth = ceil(label.intrinsicContentSize.width)
        let size = CGSize(width: textWidth + 6 * 2 + 2, height: Metrics.datePillHeight)
        pill.frame = CGRect(x: floor((bounds.width - size.width) / 2), y: floor((bounds.height - size.height) / 2), width: size.width, height: size.height)
        pill.layer.cornerRadius = size.height / 2
        dimView.frame = pill.bounds
        label.frame = pill.bounds
    }

    /// Keeps the gradient "portal" aligned with the wallpaper while scrolling.
    func updatePortal(wallpaper: WallpaperView) {
        portalView.frame = pill.convert(wallpaper.bounds, from: wallpaper)
    }
}

// MARK: - Chat header (glass navigation bar)

/// Back button (glass circle), title capsule (name + status), avatar.
/// Sources: NavigationBarNode.swift (60pt bar, row at +2+8, 16pt side insets), NavigationBarComponent.swift (44pt back capsule),
///          ChatTitleComponent.swift (44pt capsule, semibold 17 / regular 12, +28 width), ChatAvatarNavigationNode.swift (38pt avatar).
public final class ChatHeaderView: UIView {
    public let backButton: GlassButton
    public let titleCapsule: GlassView
    public let titleLabel = UILabel()
    public let subtitleLabel = UILabel()
    public let avatarView: AvatarView
    public var onBack: (() -> Void)?

    public private(set) var peer: DemoPeer

    public init(peer: DemoPeer) {
        self.peer = peer
        backButton = GlassButton(icon: Graphics.backChevron)
        titleCapsule = GlassView(interactive: true)
        avatarView = AvatarView(peer: peer)
        super.init(frame: .zero)
        addSubview(backButton)
        addSubview(titleCapsule)
        titleLabel.font = Metrics.titleFont
        titleLabel.textAlignment = .center
        subtitleLabel.font = Metrics.subtitleFont
        subtitleLabel.textAlignment = .center
        titleCapsule.contentView.addSubview(titleLabel)
        titleCapsule.contentView.addSubview(subtitleLabel)
        addSubview(avatarView)
        backButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        titleLabel.text = peer.name
        subtitleLabel.text = peer.status
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ theme: Theme) {
        backButton.glass.tint = theme.glassTint
        backButton.iconView.tintColor = theme.controlColor
        titleCapsule.tint = theme.glassTint
        titleLabel.textColor = theme.controlColor
        subtitleLabel.textColor = peer.status == "online" ? theme.onlineColor : theme.secondaryControlColor
    }

    /// Height of the bar below the status bar.
    public static let barHeight: CGFloat = 60

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: safeAreaInsets.top + Self.barHeight)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let rowY = safeAreaInsets.top + Metrics.navTopOffset
        let h = Metrics.navRowHeight
        let side = Metrics.navSideInset + safeAreaInsets.left
        backButton.frame = CGRect(x: side, y: rowY, width: h, height: h)
        avatarView.frame = CGRect(x: bounds.width - side - h + 3, y: rowY + 3, width: Metrics.navAvatarSize, height: Metrics.navAvatarSize)

        let titleSize = titleLabel.intrinsicContentSize
        let subtitleSize = subtitleLabel.intrinsicContentSize
        let maxContent = bounds.width - 2 * (side + h + 8) - 28
        let content = min(maxContent, max(ceil(max(titleSize.width, subtitleSize.width)), 150 - 28))
        let capsuleWidth = content + 28
        titleCapsule.frame = CGRect(x: floor((bounds.width - capsuleWidth) / 2), y: rowY, width: capsuleWidth, height: h)
        let textHeight = titleSize.height + subtitleSize.height
        let top = floor((h - textHeight) / 2)
        titleLabel.frame = CGRect(x: 14, y: top, width: content, height: titleSize.height)
        subtitleLabel.frame = CGRect(x: 14, y: titleLabel.frame.maxY, width: content, height: subtitleSize.height)
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains { !$0.isHidden && $0.frame.contains(point) }
    }
}

// MARK: - Input panel

/// Glass composer as Telegram draws it today: attach circle, text capsule, mic circle. With text the mic slides off to
/// the right, the field grows over its place and Send appears inside the field's right end; the sticker icon turns into
/// the emoji icon.
/// Sources (ChatTextInputPanelNode.swift unless noted):
/// - field: 40pt high (5 + 4 + 31), radius 20, x = 8 + 40 + 6; right inset 8 with text, 8 + 40 + 6 without (:1547, :2825);
///   text inset 12 from the left (:714). The width change runs as `.animated(0.4, .spring)`, i.e. Motion.spring(0.4).
/// - send: a 46 × 40 node at (field.maxX − 46, field.maxY − 40), drawn as a 40 × 34 capsule inset by 3, radius 17
///   (ChatTextInputActionButtonsNode.swift:482-498, :3716). Appears with alpha 0 → 1 over 0.2 easeInOut and scale
///   0.001 → 1 with the layout transition, 17pt to the right while hidden (:3723-3733, :4886). Pressed: scale 0.75
///   over 0.4, back over 0.25 (ChatTextInputActionButtonsNode.swift:264-268).
/// - mic: not faded; it moves to x = width + 8 with the transition (:3653-3658).
/// - accessory buttons: 32 × 40, laid out right to left from 4pt inside the field (46 more with text), no spacing,
///   the input item overlapping the next by 2 (:3461-3495); new ones scale 0.2 → 1 and fade in over 0.25.
///   Empty: stickers, and the scheduled-messages clock left of it; with text: the emoji icon only
///   (ChatInterfaceInputContexts.swift:186-263). The clock sits 1pt lower (AccessoryItemIconButton.swift:203).
public final class InputPanelView: UIView, UITextViewDelegate {
    public let attachButton: GlassButton
    public let fieldView: GlassView
    public let textView = UITextView()
    public let placeholderLabel = UILabel()
    /// Shown while the field is empty.
    public let stickerButton = UIButton(type: .custom)
    /// Shown while there is text (Telegram morphs one into the other with a Lottie; here they cross-fade).
    public let emojiButton = UIButton(type: .custom)
    /// The clock that opens the scheduled messages: shown while the field is empty and the chat has scheduled messages.
    public let scheduleButton = UIButton(type: .custom)
    public private(set) var hasScheduledMessages = false
    public var onScheduledMessages: (() -> Void)?
    public let micButton: GlassButton
    /// The 46 × 40 hit area; the visible capsule is `sendCapsule`.
    public let sendButton = UIButton(type: .custom)
    public let sendCapsule = UIView()
    private let sendIconView = UIImageView(image: Graphics.asset("TGSendIcon"))

    /// Called with the trimmed text when Send is tapped. The panel clears itself afterwards.
    public var onSend: ((String) -> Void)?
    /// Called when the text changes (after the panel relayouts).
    public var onTextChange: ((String) -> Void)?
    /// Called when the panel's height changes.
    var onHeightChange: (() -> Void)?

    public var maxLines = 6

    /// The layout state: Send shown (there is text) or not.
    private var showsSend = false

    public init() {
        attachButton = GlassButton(icon: Graphics.asset("TGIconAttachment"))
        fieldView = GlassView(interactive: true)
        micButton = GlassButton(icon: Graphics.asset("TGIconMicrophone"))
        super.init(frame: .zero)
        clipsToBounds = false
        fieldView.cornerRadius = Metrics.inputHeight / 2
        addSubview(attachButton)
        addSubview(fieldView)
        addSubview(micButton)

        textView.backgroundColor = .clear
        textView.font = Metrics.inputFont
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        fieldView.contentView.addSubview(textView)
        placeholderLabel.text = "Message"
        placeholderLabel.font = Metrics.inputFont
        fieldView.contentView.addSubview(placeholderLabel)
        stickerButton.setImage(Graphics.asset("TGAccessoryIconStickers"), for: .normal)
        fieldView.contentView.addSubview(stickerButton)
        emojiButton.setImage(Graphics.asset("TGAccessoryIconEmoji"), for: .normal)
        emojiButton.alpha = 0
        emojiButton.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        fieldView.contentView.addSubview(emojiButton)
        scheduleButton.setImage(Graphics.asset("TGAccessoryIconSchedule"), for: .normal)
        scheduleButton.alpha = 0
        scheduleButton.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        scheduleButton.addAction(UIAction { [weak self] _ in self?.onScheduledMessages?() }, for: .touchUpInside)
        fieldView.contentView.addSubview(scheduleButton)

        // Send rides on the field (above its glass), so it moves with it.
        sendCapsule.isUserInteractionEnabled = false
        sendButton.addSubview(sendCapsule)
        sendIconView.contentMode = .center
        sendCapsule.addSubview(sendIconView)
        addSubview(sendButton)
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .touchUpInside)
        sendButton.addAction(UIAction { [weak self] _ in self?.setSendPressed(true) }, for: .touchDown)
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            sendButton.addAction(UIAction { [weak self] _ in self?.setSendPressed(false) }, for: event)
        }
        sendButton.alpha = 0
        sendButton.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ theme: Theme) {
        for button in [attachButton, micButton] {
            button.glass.tint = theme.glassTint
            button.iconView.tintColor = theme.controlColor
        }
        fieldView.tint = theme.glassTint
        textView.textColor = theme.inputText
        textView.tintColor = theme.accent == .white ? UIColor(rgb: 0x0088ff) : theme.accent
        placeholderLabel.textColor = theme.inputPlaceholder
        for button in [stickerButton, emojiButton, scheduleButton] { button.tintColor = theme.inputControl }
        sendCapsule.backgroundColor = theme.sendFill
        sendIconView.tintColor = theme.sendIcon
    }

    public var text: String {
        get { textView.text }
        set { textView.text = newValue; textViewDidChange(textView) }
    }

    private var hasText: Bool { !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showsScheduleButton: Bool { hasScheduledMessages && textView.text.isEmpty }

    private func sendTapped() {
        let value = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSend?(value)
        text = ""
    }

    private func setSendPressed(_ pressed: Bool) {
        UIView.animate(withDuration: pressed ? 0.4 : 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.sendCapsule.transform = pressed ? CGAffineTransform(scaleX: 0.75, y: 0.75) : .identity
        }
    }

    /// Turns the scheduled-messages clock on or off (it shows only while the field is empty).
    public func setHasScheduledMessages(_ value: Bool, animated: Bool) {
        hasScheduledMessages = value
        updateState(animated: animated)
    }

    public func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        let old = fieldHeight
        updateState(animated: true)
        if fieldHeight != old { onHeightChange?() }
        onTextChange?(textView.text)
    }

    private func updateState(animated: Bool) {
        let typing = hasText
        let sendChanged = typing != showsSend
        showsSend = typing
        sendButton.isUserInteractionEnabled = typing
        let accessories = {
            self.setShown(self.stickerButton, !typing)
            self.setShown(self.emojiButton, typing)
            self.setShown(self.scheduleButton, self.showsScheduleButton)
        }
        guard animated else {
            accessories()
            sendButton.alpha = typing ? 1 : 0
            setNeedsLayout()
            layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: accessories)
        if sendChanged {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.sendButton.alpha = typing ? 1 : 0
            }
        }
        Motion.spring(0.4) {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }

    private func setShown(_ view: UIView, _ shown: Bool) {
        view.alpha = shown ? 1 : 0
        view.transform = shown ? .identity : CGAffineTransform(scaleX: 0.2, y: 0.2)
    }

    // MARK: Layout

    private static let sendSize = CGSize(width: 46, height: 40)
    private static let accessoryWidth: CGFloat = 32

    private func fieldFrame(height: CGFloat) -> CGRect {
        let side = Metrics.inputSideInset
        let x = side + safeAreaInsets.left + Metrics.inputHeight + Metrics.inputButtonGap
        let right = side + safeAreaInsets.right + (showsSend ? 0 : Metrics.inputHeight + Metrics.inputButtonGap)
        return CGRect(x: x, y: bounds.height - height, width: max(1, bounds.width - x - right), height: height)
    }

    /// Accessory frames in the field's coordinates, right to left, and where the text has to end.
    private func accessoryLayout(fieldWidth: CGFloat, fieldHeight: CGFloat) -> (input: CGRect, clock: CGRect, textMaxX: CGFloat) {
        var right = fieldWidth - 4 - (showsSend ? Self.sendSize.width : 0)
        let y = fieldHeight - Metrics.inputHeight
        let input = CGRect(x: right - Self.accessoryWidth, y: y, width: Self.accessoryWidth, height: Metrics.inputHeight)
        right -= Self.accessoryWidth - 2
        let clock = CGRect(x: right - Self.accessoryWidth, y: y + 1, width: Self.accessoryWidth, height: Metrics.inputHeight)
        let textMaxX = showsScheduleButton ? clock.minX : input.minX
        return (input, clock, textMaxX)
    }

    private var fieldHeight: CGFloat {
        let lineHeight = Metrics.inputFont.lineHeight
        let field = fieldFrame(height: Metrics.inputHeight)
        let width = max(1, accessoryLayout(fieldWidth: field.width, fieldHeight: Metrics.inputHeight).textMaxX - 12)
        let textHeight = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let maxHeight = lineHeight * CGFloat(maxLines) + 20
        return min(maxHeight, max(Metrics.inputHeight, ceil(textHeight)))
    }

    /// Height of the panel itself (the controls), without the bottom gap.
    public var panelHeight: CGFloat { fieldHeight }

    /// The visible Send capsule, in this panel's coordinates, where it is when shown.
    public var sendCapsuleFrame: CGRect {
        let field = fieldFrame(height: fieldHeight)
        return CGRect(x: field.maxX - Self.sendSize.width + 3, y: field.maxY - Self.sendSize.height + 3,
                      width: Self.sendSize.width - 6, height: Self.sendSize.height - 6)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: panelHeight)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let button = Metrics.inputHeight
        let height = fieldHeight
        let field = fieldFrame(height: height)
        fieldView.frame = field
        attachButton.frame = CGRect(x: Metrics.inputSideInset + safeAreaInsets.left, y: bounds.height - button, width: button, height: button)
        let micX = showsSend ? bounds.width + 8 : bounds.width - Metrics.inputSideInset - safeAreaInsets.right - button
        micButton.bounds = CGRect(x: 0, y: 0, width: button, height: button)
        micButton.center = CGPoint(x: micX + button / 2, y: bounds.height - button / 2)

        // Send: on the field's bottom-right corner; while hidden, 17pt further right and scaled to nothing.
        let sendFrame = CGRect(x: field.maxX - Self.sendSize.width, y: field.maxY - Self.sendSize.height,
                               width: Self.sendSize.width, height: Self.sendSize.height)
        sendButton.bounds = CGRect(origin: .zero, size: sendFrame.size)
        sendButton.center = CGPoint(x: sendFrame.midX + (showsSend ? 0 : 17), y: sendFrame.midY)
        sendButton.transform = showsSend ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
        sendCapsule.bounds = CGRect(x: 0, y: 0, width: sendFrame.width - 6, height: sendFrame.height - 6)
        sendCapsule.center = CGPoint(x: sendFrame.width / 2, y: sendFrame.height / 2)
        sendCapsule.layer.cornerRadius = sendCapsule.bounds.height / 2
        sendIconView.frame = sendCapsule.bounds

        let accessories = accessoryLayout(fieldWidth: field.width, fieldHeight: height)
        for (view, frame) in [(stickerButton, accessories.input), (emojiButton, accessories.input), (scheduleButton, accessories.clock)] {
            view.bounds = CGRect(origin: .zero, size: frame.size)
            view.center = CGPoint(x: frame.midX, y: frame.midY)
        }
        let textInset = (Metrics.inputHeight - Metrics.inputFont.lineHeight) / 2
        textView.textContainerInset = UIEdgeInsets(top: textInset, left: 0, bottom: textInset, right: 0)
        textView.isScrollEnabled = height >= Metrics.inputFont.lineHeight * CGFloat(maxLines)
        textView.frame = CGRect(x: 12, y: 0, width: max(1, accessories.textMaxX - 12), height: height)
        placeholderLabel.frame = CGRect(x: 12, y: textInset, width: textView.frame.width, height: Metrics.inputFont.lineHeight)
    }
}
