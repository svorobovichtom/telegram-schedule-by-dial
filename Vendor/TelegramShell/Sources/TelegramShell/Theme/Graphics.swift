import UIKit

/// Where a bubble sits in a run of messages from the same sender. Decides corners and tail.
/// Telegram's MessageBubbleImageNeighbors: single = .none, first = .top(side: false), middle = .both, last = .bottom.
public enum BubblePosition: Hashable, Sendable {
    case single, first, middle, last

    var hasTail: Bool { self == .single || self == .last }
}

/// Bubble, check and chevron images, ported from Telegram-iOS:
///   bubble:  submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift `messageBubbleImage`
///   checks:  submodules/TelegramPresentationData/Sources/PresentationThemeEssentialGraphics.swift `generateCheckImage`
///   chevron: submodules/TelegramUI/Components/NavigationBarComponent/Sources/NavigationBarGlassImages.swift
@MainActor
public enum Graphics {
    // MARK: Bubble

    /// Every iPhone the demos target is 3x.
    private static let screenScale: CGFloat = 3
    private static let fixedMainDiameter: CGFloat = 33
    private static let innerSize = CGSize(width: 33 + 6, height: 33)
    private static let margin: CGFloat = 2 // additionalInset 1 + strokeInset 1
    static var bubbleImageSize: CGSize { CGSize(width: innerSize.width + margin * 2, height: innerSize.height + margin * 2) }
    /// The bubble image is drawn in the bubble's frame outset by this.
    public static let bubbleImageOutset: CGFloat = 2

    private static let bottomEllipse = CGRect(x: 24, y: 16, width: 27, height: 17)
    private static let topEllipse = CGRect(x: 33, y: 14, width: 23, height: 21)

    private struct Radii { var tl, tr, bl, br: CGFloat }

    private static func radii(_ position: BubblePosition) -> Radii {
        let maxR = Metrics.maxCornerRadius, minR = Metrics.minCornerRadius
        switch position {
        case .single: return Radii(tl: maxR, tr: maxR, bl: maxR, br: maxR)
        case .middle: return Radii(tl: maxR, tr: minR, bl: maxR, br: minR)
        case .last:   return Radii(tl: maxR, tr: minR, bl: maxR, br: maxR)
        case .first:  return Radii(tl: maxR, tr: maxR, bl: maxR, br: minR)
        }
    }

    private static func addBody(_ c: CGContext, _ r: Radii, offset o: CGFloat = 0, close: Bool = false) {
        let d = fixedMainDiameter
        c.move(to: CGPoint(x: -o, y: r.tl + o))
        c.addArc(tangent1End: CGPoint(x: -o, y: -o), tangent2End: CGPoint(x: r.tl + o, y: -o), radius: r.tl + o * 2)
        c.addLine(to: CGPoint(x: d - r.tr - o, y: -o))
        c.addArc(tangent1End: CGPoint(x: d + o, y: -o), tangent2End: CGPoint(x: d + o, y: r.tr + o), radius: r.tr + o * 2)
        c.addLine(to: CGPoint(x: d + o, y: d - r.br - o))
        c.addArc(tangent1End: CGPoint(x: d + o, y: d + o), tangent2End: CGPoint(x: d - r.br - o, y: d + o), radius: r.br + o * 2)
        c.addLine(to: CGPoint(x: r.bl + o, y: d + o))
        c.addArc(tangent1End: CGPoint(x: -o, y: d + o), tangent2End: CGPoint(x: -o, y: d - r.bl - o), radius: r.bl + o * 2)
        if close { c.closePath() } else { c.addLine(to: CGPoint(x: -o, y: r.tl + o)) }
    }

    private static func addTailCurve(_ c: CGContext, _ e: CGRect) {
        c.move(to: CGPoint(x: e.minX, y: e.midY))
        c.addQuadCurve(to: CGPoint(x: e.midX, y: e.maxY), control: CGPoint(x: e.minX, y: e.maxY))
        c.addQuadCurve(to: CGPoint(x: e.maxX, y: e.midY), control: CGPoint(x: e.maxX, y: e.maxY))
    }

    private static func render(_ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenScale
        format.opaque = false
        return UIGraphicsImageRenderer(size: bubbleImageSize, format: format).image { ctx in
            ctx.cgContext.translateBy(x: margin, y: margin)
            draw(ctx.cgContext)
        }
    }

    /// Black bubble shape (outgoing orientation: tail at bottom right).
    private static func formImage(_ position: BubblePosition) -> UIImage {
        let r = radii(position)
        let d = fixedMainDiameter
        return render { c in
            c.setFillColor(UIColor.black.cgColor)
            addBody(c, r)
            c.fillPath()
            if position.hasTail {
                addTailCurve(c, bottomEllipse)
                c.fillPath()
                c.fill(CGRect(x: d / 2, y: floor(d / 2), width: d / 2, height: ceil(bottomEllipse.midY) - floor(d / 2)))
                c.setBlendMode(.clear)
                c.fillEllipse(in: topEllipse)
            }
        }
    }

    /// Black hairline outline of the same shape.
    private static func outlineImage(_ position: BubblePosition) -> UIImage {
        let r = radii(position)
        let d = fixedMainDiameter
        let pixel = 1 / screenScale
        let innerExtension: CGFloat = 0.25
        let borderWidth = pixel + innerExtension
        let borderOffset = abs(pixel - 0.5) < .ulpOfOne ? -innerExtension / 2 + pixel / 2 : -innerExtension / 2
        let outlineBottomEllipse = bottomEllipse.insetBy(dx: -borderOffset, dy: -borderOffset)
        let outlineInnerTopEllipse = topEllipse.insetBy(dx: borderOffset, dy: borderOffset)

        let tail: UIImage? = position.hasTail ? render { c in
            c.setStrokeColor(UIColor.black.cgColor)
            c.setLineWidth(borderWidth)
            addTailCurve(c, outlineBottomEllipse)
            c.strokePath()
            c.setBlendMode(.clear)
            c.fillEllipse(in: outlineInnerTopEllipse)
            addBody(c, r)
            c.fillPath()
            c.setBlendMode(.normal)
            // The concave edge of the tail: the inner ellipse, only where it crosses the lower half of the tail.
            c.saveGState()
            c.addEllipse(in: CGRect(x: bottomEllipse.minX + 1 - borderOffset - 1, y: bottomEllipse.minY + 1 - borderOffset - 1, width: outlineBottomEllipse.width, height: outlineBottomEllipse.height))
            c.clip()
            c.clip(to: CGRect(x: bottomEllipse.minX - 1, y: bottomEllipse.midY, width: bottomEllipse.width + 2, height: bottomEllipse.height))
            c.strokeEllipse(in: outlineInnerTopEllipse)
            c.restoreGState()
        } : nil

        return render { c in
            c.setStrokeColor(UIColor.black.cgColor)
            c.setLineWidth(borderWidth)
            addBody(c, r, offset: borderOffset, close: true)
            c.strokePath()
            if let tail {
                c.setBlendMode(.clear)
                addTailCurve(c, bottomEllipse)
                c.fillPath()
                c.fill(CGRect(x: floor(d / 2), y: d / 2, width: d / 2 + borderWidth, height: ceil(bottomEllipse.midY) - floor(d / 2)))
                c.setBlendMode(.normal)
                c.move(to: CGPoint(x: d + borderOffset, y: d / 2))
                c.addLine(to: CGPoint(x: d + borderOffset, y: outlineBottomEllipse.midY))
                c.strokePath()
                c.translateBy(x: -margin, y: -margin)
                tail.draw(in: CGRect(origin: .zero, size: bubbleImageSize))
            }
        }
    }

    public enum BubbleLayer: Hashable, Sendable { case form, outline }

    private struct BubbleKey: Hashable { var incoming: Bool; var position: BubblePosition; var layer: BubbleLayer }
    private static var bubbleCache: [BubbleKey: UIImage] = [:]

    /// Resizable template image for one layer of a bubble. Tint it (UIImageView.tintColor) or use it as a mask.
    public static func bubbleImage(incoming: Bool, position: BubblePosition, layer: BubbleLayer) -> UIImage {
        let key = BubbleKey(incoming: incoming, position: position, layer: layer)
        if let cached = bubbleCache[key] { return cached }
        var image = layer == .form ? formImage(position) : outlineImage(position)
        if incoming {
            image = UIGraphicsImageRenderer(size: image.size, format: image.imageRendererFormat).image { ctx in
                ctx.cgContext.translateBy(x: image.size.width, y: 0)
                ctx.cgContext.scaleBy(x: -1, y: 1)
                image.draw(at: .zero)
            }
        }
        // Stretch point from messageBubbleImage: x = 1 + 1 + round(33/2) - 1 (mirrored for incoming), y = 1 + 1 + round(33/2).
        let size = bubbleImageSize
        let outgoingX: CGFloat = 1 + 1 + 17 - 1
        let x = incoming ? (innerSize.width + 2) - outgoingX + 1 : outgoingX
        let y: CGFloat = 1 + 1 + 17
        let resizable = image.withRenderingMode(.alwaysTemplate).resizableImage(
            withCapInsets: UIEdgeInsets(top: y, left: x, bottom: size.height - y - 1, right: size.width - x - 1),
            resizingMode: .stretch
        )
        bubbleCache[key] = resizable
        return resizable
    }

    // MARK: Checks

    /// 11 × 9 template check. `partial` is the second check of "read".
    public static func checkImage(partial: Bool) -> UIImage {
        let width = Metrics.checkWidth
        let size = CGSize(width: width, height: floor(width * 9 / 11))
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.scaleBy(x: width / 11, y: width / 11)
            c.translateBy(x: 1, y: 1)
            c.setStrokeColor(UIColor.black.cgColor)
            c.setLineWidth(0.99)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            if partial {
                c.move(to: CGPoint(x: 0.5, y: 7)); c.addLine(to: CGPoint(x: 7, y: 0))
            } else {
                c.move(to: CGPoint(x: 0, y: 4)); c.addLine(to: CGPoint(x: 2.95157047, y: 6.95157047))
                c.addLine(to: CGPoint(x: 3.04660389, y: 6.9498112)); c.addLine(to: CGPoint(x: 9.5, y: 0))
            }
            c.strokePath()
        }.withRenderingMode(.alwaysTemplate)
    }

    // MARK: Navigation

    /// 44 × 44 back chevron, 2pt round stroke.
    public static let backChevron: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44)).image { ctx in
        let c = ctx.cgContext
        c.setStrokeColor(UIColor.black.cgColor)
        c.setLineWidth(2)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.move(to: CGPoint(x: 24.6, y: 14)); c.addLine(to: CGPoint(x: 17, y: 22)); c.addLine(to: CGPoint(x: 24.6, y: 30))
        c.strokePath()
    }.withRenderingMode(.alwaysTemplate)

    /// A demo photo from the app bundle, by file name.
    public static func photo(_ name: String) -> UIImage? {
        UIImage(named: name) ?? UIImage(named: name, in: .module, with: nil)
    }

    public static func asset(_ name: String) -> UIImage? {
        UIImage(named: name, in: .module, with: nil)?.withRenderingMode(.alwaysTemplate)
    }
}
