import UIKit
import TelegramShell

/// A one-line label whose changed characters roll, like SwiftUI's `.contentTransition(.numericText())`: the part both
/// texts share stays (and slides to its new place if the width changes), each changed character leaves upward and the
/// new one comes in from below (or the other way round with `.down`), fading as it goes. "19:47" → "20:17" rolls only
/// "1 9 4"; "in 15 min" → "in 30 min" only "15".
///
/// One UILabel per character, laid out by advance width; use a font with monospaced digits so times don't jitter.
@MainActor
final class RollingLabel: UIView {
    enum Direction { case up, down }

    let font: UIFont
    var textColor: UIColor {
        didSet { glyphs.forEach { $0.label.textColor = textColor } }
    }
    /// .left, .center or .right inside the bounds.
    let alignment: NSTextAlignment
    private(set) var text = ""

    private struct Glyph {
        let character: Character
        let label: UILabel
        let width: CGFloat
    }
    private var glyphs: [Glyph] = []

    init(font: UIFont, textColor: UIColor, alignment: NSTextAlignment = .left) {
        self.font = font
        self.textColor = textColor
        self.alignment = alignment
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    var lineHeight: CGFloat { ceil(font.lineHeight) }

    func width(of text: String) -> CGFloat {
        ceil(text.reduce(0) { $0 + advance($1) })
    }

    var contentWidth: CGFloat { glyphs.reduce(0) { $0 + $1.width } }

    override var intrinsicContentSize: CGSize { CGSize(width: ceil(contentWidth), height: lineHeight) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    private func advance(_ character: Character) -> CGFloat {
        (String(character) as NSString).size(withAttributes: [.font: font]).width
    }

    func setText(_ new: String, direction: Direction = .up, animated: Bool = true) {
        guard new != text else { return }
        let old = Array(text), next = Array(new)
        let animated = animated && !old.isEmpty && window != nil
        text = new

        // Shared start and end stay; the middle rolls, except characters that match position for position when the
        // middles are the same length (a time: only the changed digits roll).
        var prefix = 0
        while prefix < old.count, prefix < next.count, old[prefix] == next[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < next.count - prefix,
              old[old.count - 1 - suffix] == next[next.count - 1 - suffix] { suffix += 1 }
        let sameLength = old.count == next.count

        var kept = Set<Int>()
        var result: [Glyph] = []
        var entering: [Glyph] = []
        for (i, character) in next.enumerated() {
            var source: Int?
            if i < prefix {
                source = i
            } else if i >= next.count - suffix {
                source = old.count - (next.count - i)
            } else if sameLength, old[i] == character {
                source = i
            }
            if let source {
                kept.insert(source)
                result.append(glyphs[source])
            } else {
                let label = UILabel()
                label.text = String(character)
                label.font = font
                label.textColor = textColor
                addSubview(label)
                let glyph = Glyph(character: character, label: label, width: advance(character))
                result.append(glyph)
                entering.append(glyph)
            }
        }
        let leaving = glyphs.indices.filter { !kept.contains($0) }.map { glyphs[$0] }
        glyphs = result

        let frames = layoutFrames()
        guard animated else {
            leaving.forEach { $0.label.removeFromSuperview() }
            for (glyph, frame) in zip(glyphs, frames) {
                glyph.label.frame = frame
                glyph.label.alpha = 1
                glyph.label.transform = .identity
            }
            return
        }

        let shift = lineHeight * 0.6 * (direction == .up ? 1 : -1)
        let out = CGAffineTransform(translationX: 0, y: -shift).scaledBy(x: 0.8, y: 0.8)
        let into = CGAffineTransform(translationX: 0, y: shift).scaledBy(x: 0.8, y: 0.8)
        for glyph in entering {
            guard let index = glyphs.firstIndex(where: { $0.label === glyph.label }) else { continue }
            UIView.performWithoutAnimation {
                glyph.label.frame = frames[index]
                glyph.label.transform = into
                glyph.label.alpha = 0
            }
        }
        // Telegram's .spring(0.35) curve, so nothing overshoots; leaving characters go a little faster.
        Motion.spring(0.35) {
            for (glyph, frame) in zip(self.glyphs, frames) {
                glyph.label.transform = .identity
                glyph.label.center = CGPoint(x: frame.midX, y: frame.midY)
                glyph.label.alpha = 1
            }
        }
        for glyph in leaving {
            Motion.spring(0.25) {
                glyph.label.transform = out
            } completion: { _ in
                glyph.label.removeFromSuperview()
            }
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                glyph.label.alpha = 0
            }
        }
    }

    private func layoutFrames() -> [CGRect] {
        let total = contentWidth
        var x: CGFloat
        switch alignment {
        case .center: x = (bounds.width - total) / 2
        case .right: x = bounds.width - total
        default: x = 0
        }
        let height = lineHeight
        let y = (bounds.height - height) / 2
        return glyphs.map { glyph in
            defer { x += glyph.width }
            return CGRect(x: x, y: y, width: ceil(glyph.width) + 1, height: height)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keeps the text in place when the label is resized (the transforms of rolling characters are left alone).
        for (glyph, frame) in zip(glyphs, layoutFrames()) {
            glyph.label.bounds = CGRect(origin: .zero, size: frame.size)
            glyph.label.center = CGPoint(x: frame.midX, y: frame.midY)
        }
    }
}
