import UIKit
import CoreText

/// Message text drawn with Core Text, so layout is exact and a concept can reach every line and glyph
/// (`lineRects`, `glyphRects`) — e.g. to animate letters one by one.
/// Line height = ascent + descent, +12% between lines (InteractiveTextComponent default lineSpacing 0.12).
public final class MessageTextView: UIView {
    public struct Layout {
        public var size: CGSize
        public var lastLineWidth: CGFloat
        public var lineCount: Int
        fileprivate var frame: CTFrame
    }

    public private(set) var attributedText: NSAttributedString = NSAttributedString()
    public private(set) var layout: Layout?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    public static func attributedString(_ text: String, color: UIColor, font: UIFont = Metrics.messageFont) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (font.ascender - font.descender) * Metrics.lineSpacingFactor
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    public static func measure(_ string: NSAttributedString, maxWidth: CGFloat) -> Layout {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let height = ceil(suggested.height)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: height + 1), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var maxLineWidth: CGFloat = 0
        var lastLineWidth: CGFloat = 0
        for line in lines {
            let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
            maxLineWidth = max(maxLineWidth, w)
            lastLineWidth = w
        }
        return Layout(size: CGSize(width: ceil(maxLineWidth), height: height), lastLineWidth: ceil(lastLineWidth), lineCount: lines.count, frame: frame)
    }

    public func setText(_ string: NSAttributedString, maxWidth: CGFloat) {
        attributedText = string
        layout = Self.measure(string, maxWidth: maxWidth)
        setNeedsDisplay()
    }

    public override func draw(_ rect: CGRect) {
        guard let layout, let context = UIGraphicsGetCurrentContext() else { return }
        let pathHeight = CTFramePathHeight(layout.frame)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: pathHeight)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(layout.frame, context)
        context.restoreGState()
    }

    /// Bounding rect of each line, in this view's coordinates.
    public var lineRects: [CGRect] {
        guard let layout else { return [] }
        let lines = CTFrameGetLines(layout.frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(layout.frame, CFRange(), &origins)
        let pathHeight = CTFramePathHeight(layout.frame)
        return zip(lines, origins).map { line, origin in
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            return CGRect(x: origin.x, y: pathHeight - origin.y - ascent, width: CGFloat(width), height: ascent + descent)
        }
    }

    /// Rect of every character (UTF-16 index → rect), in this view's coordinates.
    public var glyphRects: [(index: Int, rect: CGRect)] {
        guard let layout else { return [] }
        let lines = CTFrameGetLines(layout.frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(layout.frame, CFRange(), &origins)
        let pathHeight = CTFramePathHeight(layout.frame)
        var result: [(Int, CGRect)] = []
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let range = CTLineGetStringRange(line)
            for i in range.location ..< range.location + range.length {
                let x0 = CTLineGetOffsetForStringIndex(line, i, nil)
                let x1 = CTLineGetOffsetForStringIndex(line, i + 1, nil)
                guard x1 > x0 else { continue }
                result.append((i, CGRect(x: origin.x + x0, y: pathHeight - origin.y - ascent, width: x1 - x0, height: ascent + descent)))
            }
        }
        return result
    }
}

private func CTFramePathHeight(_ frame: CTFrame) -> CGFloat {
    CTFrameGetPath(frame).boundingBox.height
}
