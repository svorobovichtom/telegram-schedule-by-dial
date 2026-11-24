import UIKit

/// The fill + hairline outline of a bubble, sized to the bubble's frame (tail column included).
/// Fill is a tinted template image, or a screen-space vertical gradient masked by it (Night outgoing).
public final class BubbleBackgroundView: UIView {
    public private(set) var incoming: Bool
    public private(set) var position: BubblePosition

    private let fillView = UIImageView()
    private let outlineView = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let gradientMaskView = UIImageView()

    public init(incoming: Bool, position: BubblePosition) {
        self.incoming = incoming
        self.position = position
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(fillView)
        layer.addSublayer(gradientLayer)
        gradientLayer.mask = gradientMaskView.layer
        addSubview(outlineView)
        updateImages()
    }

    required init?(coder: NSCoder) { fatalError() }

    public func update(incoming: Bool, position: BubblePosition) {
        guard incoming != self.incoming || position != self.position else { return }
        self.incoming = incoming
        self.position = position
        updateImages()
    }

    private func updateImages() {
        let form = Graphics.bubbleImage(incoming: incoming, position: position, layer: .form)
        fillView.image = form
        gradientMaskView.image = form
        outlineView.image = Graphics.bubbleImage(incoming: incoming, position: position, layer: .outline)
    }

    public func apply(_ bubble: Theme.Bubble) {
        if bubble.fill.count > 1 {
            fillView.isHidden = true
            gradientLayer.isHidden = false
            gradientLayer.colors = bubble.fill.map(\.cgColor)
        } else {
            fillView.isHidden = false
            fillView.tintColor = bubble.fill.first
            gradientLayer.isHidden = true
        }
        outlineView.tintColor = bubble.stroke
        outlineView.isHidden = bubble.stroke.cgColor.alpha == 0
    }

    /// Screen-space gradient: pass the window's bounds converted to this view's coordinates.
    func setGradientViewport(_ rect: CGRect) {
        guard !gradientLayer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = rect
        gradientMaskView.frame = imageFrame.offsetBy(dx: -rect.minX, dy: -rect.minY)
        CATransaction.commit()
    }

    private var imageFrame: CGRect { bounds.insetBy(dx: -Graphics.bubbleImageOutset, dy: -Graphics.bubbleImageOutset) }

    public override func layoutSubviews() {
        super.layoutSubviews()
        fillView.frame = imageFrame
        outlineView.frame = imageFrame
        if gradientLayer.frame == .zero {
            setGradientViewport(bounds)
        } else {
            // A resize keeps the viewport; the mask follows the bubble (and animates with it).
            gradientMaskView.frame = imageFrame.offsetBy(dx: -gradientLayer.frame.minX, dy: -gradientLayer.frame.minY)
        }
    }
}

/// One message row: full chat width, bubble placed left (incoming) or right (outgoing).
public final class MessageView: UIView {
    public private(set) var message: DemoMessage
    public private(set) var position: BubblePosition
    public private(set) var theme: Theme

    /// Bubble frame including the 6pt tail column, in this view's coordinates.
    public private(set) var bubbleFrame: CGRect = .zero
    /// Bubble frame without the tail column (the rounded body).
    public var bodyFrame: CGRect {
        message.isOutgoing
            ? CGRect(x: bubbleFrame.minX, y: bubbleFrame.minY, width: bubbleFrame.width - Metrics.tailWidth, height: bubbleFrame.height)
            : CGRect(x: bubbleFrame.minX + Metrics.tailWidth, y: bubbleFrame.minY, width: bubbleFrame.width - Metrics.tailWidth, height: bubbleFrame.height)
    }

    /// Holds background + text + status; move or transform this to move the whole bubble.
    public let bubbleView = UIView()
    public let backgroundView: BubbleBackgroundView
    public let textView = MessageTextView()
    /// A photo message's images (one, or an album's tiles) and the dark pill its time sits on
    /// (ChatMessageInteractiveMediaNode). The tiles share one mask: the album's outer shape.
    public let photoView = UIView()
    private var photoTiles: [UIImageView] = []
    private let photoMask = UIView()
    private let photoMaskShape = CAShapeLayer()
    private let photoMaskTailClip = UIView()
    private let photoMaskTail = UIImageView()
    private let statusPill = UIView()
    public let dateLabel = UILabel()
    public let checkView = UIImageView(image: Graphics.checkImage(partial: false))
    public let secondCheckView = UIImageView(image: Graphics.checkImage(partial: true))

    init(message: DemoMessage, position: BubblePosition, theme: Theme) {
        self.message = message
        self.position = position
        self.theme = theme
        backgroundView = BubbleBackgroundView(incoming: !message.isOutgoing, position: position)
        super.init(frame: .zero)
        addSubview(bubbleView)
        bubbleView.addSubview(backgroundView)
        bubbleView.addSubview(textView)
        photoView.clipsToBounds = true
        for name in message.photos {
            let tile = UIImageView(image: Graphics.photo(name))
            tile.contentMode = .scaleAspectFill
            tile.clipsToBounds = true
            photoView.addSubview(tile)
            photoTiles.append(tile)
        }
        photoMask.layer.addSublayer(photoMaskShape)
        photoMaskTailClip.clipsToBounds = true
        photoMaskTailClip.addSubview(photoMaskTail)
        photoMask.addSubview(photoMaskTailClip)
        photoView.mask = photoMask
        photoView.isHidden = message.photo == nil
        bubbleView.addSubview(photoView)
        statusPill.backgroundColor = Metrics.imageStatusFill
        statusPill.isHidden = message.photo == nil
        bubbleView.addSubview(statusPill)
        textView.isHidden = message.photo != nil
        dateLabel.font = Metrics.dateFont
        bubbleView.addSubview(dateLabel)
        bubbleView.addSubview(checkView)
        bubbleView.addSubview(secondCheckView)
        apply(theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var colors: Theme.Bubble { message.isOutgoing ? theme.outgoing : theme.incoming }

    func apply(_ theme: Theme) {
        self.theme = theme
        backgroundView.apply(colors)
        let onPhoto = message.photo != nil
        dateLabel.textColor = onPhoto ? .white : colors.secondaryText
        dateLabel.text = Self.timeFormatter.string(from: message.date)
        checkView.tintColor = onPhoto ? .white : colors.checkmark
        secondCheckView.tintColor = onPhoto ? .white : colors.checkmark
        updateStatus()
        setNeedsLayout()
    }

    func update(position: BubblePosition) {
        self.position = position
        backgroundView.update(incoming: !message.isOutgoing, position: position)
    }

    public func update(status: DemoMessage.Status) {
        message.status = status
        updateStatus()
    }

    private func updateStatus() {
        checkView.isHidden = !message.isOutgoing || message.status == .sending
        secondCheckView.isHidden = !message.isOutgoing || message.status != .read
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: Layout (ChatMessageTextBubbleContentNode + ChatMessageDateAndStatusNode)

    struct Layout {
        var height: CGFloat
        var bubble: CGRect
        var text: CGRect
        var date: CGRect
        var check: CGRect
        var secondCheck: CGRect
        var textMaxWidth: CGFloat
        var photo: CGRect = .zero
        /// An album's tiles, in the coordinates of `photo`.
        var tiles: [CGRect] = []
        var statusPill: CGRect = .zero
        /// How far the photo sits inside the bubble.
        var photoInset: CGFloat = Metrics.imageInset
    }

    /// A photo message: the image fitted into 300 × 380 (at least 170 × 74), 2pt inside the bubble (1pt over a
    /// single-color wallpaper, where only the bubble's stroke has to stay clear), the time on a dark pill 6pt from
    /// the image's bottom right corner.
    private static func photoLayout(message: DemoMessage, images: [UIImage], width: CGFloat, safeInsets: UIEdgeInsets, inset: CGFloat) -> Layout {
        let maxWidth = min(Metrics.imageMaxSize.width, Metrics.maxBubbleWidth(for: width) - Metrics.tailWidth - 2 * inset)
        let size: CGSize
        var tiles: [CGRect]
        if images.count == 2 {
            // fittedToWidthOrSmaller (Display/UIKitUtils.swift)
            let available = Metrics.maxBubbleWidth(for: width) - Metrics.tailWidth - 2 * inset
            let fit = min(1, available / Metrics.imageMaxSize.width)
            let maxSize = CGSize(width: floor(Metrics.imageMaxSize.width * fit), height: floor(Metrics.imageMaxSize.height * fit))
            (tiles, size) = mosaic(maxSize: maxSize, sizes: images.map(\.size))
        } else {
            let image = images[0]
            let scale = min(maxWidth / image.size.width, Metrics.imageMaxSize.height / image.size.height)
            size = CGSize(width: max(Metrics.imageMinSize.width, floor(image.size.width * scale)),
                          height: max(Metrics.imageMinSize.height, floor(image.size.height * scale)))
            tiles = [CGRect(origin: .zero, size: size)]
        }
        let bodyWidth = size.width + 2 * inset
        let bodyHeight = size.height + 2 * inset
        let bubbleWidth = bodyWidth + Metrics.tailWidth
        let bubbleX = message.isOutgoing
            ? width - safeInsets.right - Metrics.bubbleEdgeInset - bubbleWidth
            : safeInsets.left + Metrics.bubbleEdgeInset
        let bodyX = message.isOutgoing ? 0 : Metrics.tailWidth
        let photo = CGRect(x: bodyX + inset, y: inset, width: size.width, height: size.height)

        let dateSize = (timeFormatter.string(from: message.date) as NSString).size(withAttributes: [.font: Metrics.dateFont])
        let dateWidth = ceil(dateSize.width), dateHeight = ceil(dateSize.height)
        let padding = Metrics.imageStatusPadding
        let pillWidth = padding.left + dateWidth + (message.isOutgoing ? 5 + Metrics.statusWidth : 0) + padding.right
        let pill = CGRect(x: photo.maxX - Metrics.imageStatusInset - pillWidth, y: photo.maxY - Metrics.imageStatusInset - dateHeight - padding.top - padding.bottom,
                          width: pillWidth, height: dateHeight + padding.top + padding.bottom)
        let date = CGRect(x: pill.minX + padding.left, y: pill.minY + padding.top, width: dateWidth, height: dateHeight)
        let checkSize = CGSize(width: Metrics.checkWidth, height: floor(Metrics.checkWidth * 9 / 11))
        let checkY = date.minY + 3 - Metrics.pixel
        let readCheckX = date.maxX + 5 + Metrics.statusWidth - Metrics.checkWidth
        return Layout(
            height: bodyHeight,
            bubble: CGRect(x: bubbleX, y: 0, width: bubbleWidth, height: bodyHeight),
            text: .zero,
            date: date,
            check: CGRect(origin: CGPoint(x: readCheckX - Metrics.checkOffset, y: checkY), size: checkSize),
            secondCheck: CGRect(origin: CGPoint(x: readCheckX, y: checkY), size: checkSize),
            textMaxWidth: 0,
            photo: photo,
            tiles: tiles,
            statusPill: pill,
            photoInset: inset
        )
    }

    static func layout(message: DemoMessage, width: CGFloat, safeInsets: UIEdgeInsets, plainWallpaper: Bool = false) -> Layout {
        let images = message.photos.prefix(2).compactMap(Graphics.photo)
        if !images.isEmpty {
            return photoLayout(message: message, images: images, width: width, safeInsets: safeInsets,
                               inset: plainWallpaper ? 1 : Metrics.imageInset)
        }
        let insets = Metrics.textInsets
        let maxBubble = Metrics.maxBubbleWidth(for: width)
        let maxText = floor(maxBubble - Metrics.bubbleEdgeInset * 3 - Metrics.tailWidth - insets.left - insets.right)
        let text = MessageTextView.measure(MessageTextView.attributedString(message.text, color: .black), maxWidth: maxText)

        let dateText = timeFormatter.string(from: message.date) as NSString
        let dateSize = dateText.size(withAttributes: [.font: Metrics.dateFont])
        let dateWidth = ceil(dateSize.width)
        let dateHeight = ceil(dateSize.height)
        // Status: 5pt gap, date, and for outgoing the 13pt check slot after a 5pt gap.
        let statusWidth = 5 + dateWidth + (message.isOutgoing ? 5 + Metrics.statusWidth : 0)

        var contentWidth = text.size.width
        var contentHeight = text.size.height
        if text.lastLineWidth + statusWidth <= maxText {
            contentWidth = max(contentWidth, text.lastLineWidth + statusWidth)
        } else {
            contentWidth = max(contentWidth, statusWidth)
            contentHeight += dateHeight
        }

        let bodyWidth = max(Metrics.minBubbleSize.width, contentWidth + insets.left + insets.right)
        let bodyHeight = max(Metrics.minBubbleSize.height, contentHeight + insets.top + insets.bottom)
        let bubbleWidth = bodyWidth + Metrics.tailWidth

        let bubbleX = message.isOutgoing
            ? width - safeInsets.right - Metrics.bubbleEdgeInset - bubbleWidth
            : safeInsets.left + Metrics.bubbleEdgeInset
        let bubble = CGRect(x: bubbleX, y: 0, width: bubbleWidth, height: bodyHeight)
        let bodyX = message.isOutgoing ? 0 : Metrics.tailWidth

        let textFrame = CGRect(x: bodyX + insets.left, y: insets.top, width: text.size.width, height: text.size.height)
        // Status sits at the bottom-right of the body.
        let statusRight = bodyX + bodyWidth - insets.right + (message.isOutgoing ? 2 : 0)
        let dateY = bodyHeight - insets.bottom - dateHeight + 1
        let checkSlotX = statusRight - Metrics.statusWidth
        let dateX = message.isOutgoing ? checkSlotX - 5 - dateWidth : statusRight - dateWidth
        let checkSize = CGSize(width: Metrics.checkWidth, height: floor(Metrics.checkWidth * 9 / 11))
        let checkY = dateY + 3 - Metrics.pixel
        let readCheckX = checkSlotX + Metrics.statusWidth - Metrics.checkWidth
        return Layout(
            height: bodyHeight,
            bubble: bubble,
            text: textFrame,
            date: CGRect(x: dateX, y: dateY, width: dateWidth, height: dateHeight),
            check: CGRect(origin: CGPoint(x: readCheckX - Metrics.checkOffset, y: checkY), size: checkSize),
            secondCheck: CGRect(origin: CGPoint(x: readCheckX, y: checkY), size: checkSize),
            textMaxWidth: maxText
        )
    }

    func apply(_ layout: Layout, width: CGFloat) {
        bubbleFrame = layout.bubble
        bubbleView.frame = layout.bubble
        backgroundView.frame = bubbleView.bounds
        if message.photo == nil {
            textView.setText(MessageTextView.attributedString(message.text, color: colors.text), maxWidth: layout.textMaxWidth)
            textView.frame = layout.text
        } else {
            layoutPhoto(layout.photo, tiles: layout.tiles, inset: layout.photoInset)
            statusPill.frame = layout.statusPill
            statusPill.layer.cornerRadius = layout.statusPill.height / 2
        }
        dateLabel.frame = layout.date
        // A single sent check takes the read position; read shows both, offset by checkOffset.
        if message.status == .read {
            checkView.frame = layout.check
            secondCheckView.frame = layout.secondCheck
        } else {
            checkView.frame = layout.secondCheck
        }
    }

    /// Two photos side by side or stacked, 1pt apart: the two-item cases of chatMessageBubbleMosaicLayout
    /// (MosaicLayout/Sources/ChatMessageBubbleMosaicLayout.swift).
    static func mosaic(maxSize: CGSize, sizes: [CGSize], spacing: CGFloat = 1) -> ([CGRect], CGSize) {
        let ratios = sizes.map { $0.height == 0 ? 1 : $0.width / $0.height }
        let proportions = ratios.map { $0 > 1.2 ? "w" : $0 < 0.8 ? "n" : "q" }.joined()
        let average = (1 + ratios.reduce(0, +)) / CGFloat(ratios.count)
        let maxRatio = maxSize.width / maxSize.height
        let frames: [CGRect]
        if proportions == "ww" && average > 1.4 * maxRatio && ratios[1] - ratios[0] < 0.2 {
            let width = maxSize.width
            let height = floor(min(width / ratios[0], min(width / ratios[1], (maxSize.height - spacing) / 2)))
            frames = [CGRect(x: 0, y: 0, width: width, height: height), CGRect(x: 0, y: height + spacing, width: width, height: height)]
        } else if proportions == "ww" || proportions == "qq" {
            let width = (maxSize.width - spacing) / 2
            let height = floor(min(width / ratios[0], min(width / ratios[1], maxSize.height)))
            frames = [CGRect(x: 0, y: 0, width: width, height: height), CGRect(x: width + spacing, y: 0, width: width, height: height)]
        } else {
            let available = maxSize.width - spacing
            let second = floor(min(0.5 * available, (available / ratios[0] / (1 / ratios[0] + 1 / ratios[1])).rounded()))
            let first = maxSize.width - second - spacing
            let height = floor(min(maxSize.height, min(first / ratios[0], second / ratios[1]).rounded()))
            frames = [CGRect(x: 0, y: 0, width: first, height: height), CGRect(x: first + spacing, y: 0, width: second, height: height)]
        }
        let union = frames.reduce(CGRect.null) { $0.union($1) }
        return (frames, union.size)
    }

    /// The photo's shape (ChatMessageBubbleContentCalclulateImageCorners.swift, mediaBubbleCornerImage): 15pt corners,
    /// 7pt where the bubble is merged with its neighbour, and next to the tail the photo follows the bubble's own
    /// outline, 2pt inside it, into the tail.
    private func layoutPhoto(_ image: CGRect, tiles: [CGRect], inset: CGFloat) {
        let incoming = !message.isOutgoing
        let hasTail = position == .single || position == .last
        // With a tail the photo also covers the tail column.
        var frame = image
        if hasTail {
            frame.size.width += Metrics.tailWidth
            if incoming { frame.origin.x -= Metrics.tailWidth }
        }
        photoView.frame = frame
        photoMask.frame = photoView.bounds
        let body = image.offsetBy(dx: -frame.minX, dy: -frame.minY)
        // Tiles on the album's outer edge reach past it (into the tail column); the mask cuts them to shape. The 1pt
        // gaps between tiles show the bubble.
        for (tile, rect) in zip(photoTiles, tiles) {
            var r = rect.offsetBy(dx: body.minX, dy: body.minY)
            if rect.minX <= 0 { r.size.width += r.minX; r.origin.x = 0 }
            if rect.maxX >= image.width { r.size.width = frame.width - r.minX }
            tile.frame = r
        }

        let normal = Metrics.imageCornerRadius, merged: CGFloat = 7
        let top = position == .single || position == .first ? normal : merged
        let bottom = position == .first || position == .middle ? merged : normal
        // The sender's side merges; the far side keeps full corners.
        let radii = incoming ? (tl: top, tr: normal, br: normal, bl: bottom) : (tl: normal, tr: top, br: bottom, bl: normal)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: body.minX + radii.tl, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - radii.tr, y: body.minY))
        path.addArc(withCenter: CGPoint(x: body.maxX - radii.tr, y: body.minY + radii.tr), radius: radii.tr, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radii.br))
        path.addArc(withCenter: CGPoint(x: body.maxX - radii.br, y: body.maxY - radii.br), radius: radii.br, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: body.minX + radii.bl, y: body.maxY))
        path.addArc(withCenter: CGPoint(x: body.minX + radii.bl, y: body.maxY - radii.bl), radius: radii.bl, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radii.tl))
        path.addArc(withCenter: CGPoint(x: body.minX + radii.tl, y: body.minY + radii.tl), radius: radii.tl, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        path.close()
        photoMaskShape.path = path.cgPath

        // The tail corner: the bubble's own form, 2pt smaller, shown only around that corner.
        photoMaskTailClip.isHidden = !hasTail
        guard hasTail else { return }
        let corner: CGFloat = 20
        photoMaskTailClip.frame = CGRect(x: incoming ? 0 : photoView.bounds.width - corner - Metrics.tailWidth, y: photoView.bounds.height - corner,
                                         width: corner + Metrics.tailWidth, height: corner)
        photoMaskTail.image = Graphics.bubbleImage(incoming: incoming, position: position, layer: .form)
        // The bubble image has a 2pt margin around the form: at the bubble's own bounds the form sits 2pt inside it.
        let margin = Graphics.bubbleImageOutset - inset
        let bubble = bubbleView.bounds.insetBy(dx: -margin, dy: -margin).offsetBy(dx: -frame.minX, dy: -frame.minY)
        photoMaskTail.frame = bubble.offsetBy(dx: -photoMaskTailClip.frame.minX, dy: -photoMaskTailClip.frame.minY)
    }

    /// Keeps a screen-space gradient fill (Night outgoing) fixed to the screen while scrolling.
    func updateScreenGradient() {
        guard let window else { return }
        backgroundView.setGradientViewport(backgroundView.convert(window.bounds, from: window))
    }
}
