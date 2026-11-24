import UIKit
import Accelerate

/// Telegram's default chat wallpaper: a 4-color "swirl" gradient with the doodle pattern on top.
///   gradient: submodules/GradientBackground/Sources/SoftwareGradientBackground.swift (generateGradient, basePositions, phases)
///   pattern:  submodules/TelegramUI/Resources/fqv01SQemVIBAAAApND8LDRUhRU.tgv (pre-rendered to WallpaperPattern.png)
///   compose:  submodules/WallpaperBackgroundNode/Sources/WallpaperBackgroundNode.swift (updatePatternPresentation):
///             intensity ≥ 0 → black pattern at `intensity` opacity, soft light over the gradient (Day Classic, 0.5);
///             intensity < 0 → black background, gradient shown through the pattern at |intensity| (Night, 0.34).
public final class WallpaperView: UIView {
    public private(set) var theme: Theme.Wallpaper
    public private(set) var phase: Int = 0

    private let gradientView = UIImageView()
    private let patternView = UIImageView()
    private let patternMaskView = UIImageView()
    private var renderedSize: CGSize = .zero

    /// False draws the wallpaper without its pattern: the gradient alone, or plain black for an inverted (dark)
    /// pattern. Telegram's edge effect is made of exactly that (WallpaperEdgeEffectNodeImpl: the gradient clone
    /// and a black overlay for inverted patterns; the pattern layer is left out).
    public var showsPattern = true { didSet { apply() } }

    /// The gradient at saturation 1.7, for service pills (ChatMessageDateHeader's wallpaper "portal").
    public private(set) var dimmedGradientImage: UIImage?

    public init(theme: Theme.Wallpaper) {
        self.theme = theme
        super.init(frame: .zero)
        clipsToBounds = true
        gradientView.contentMode = .scaleToFill
        gradientView.layer.magnificationFilter = .linear
        addSubview(gradientView)
        let pattern = UIImage(named: "WallpaperPattern", in: .module, with: nil)
        patternView.image = pattern?.withRenderingMode(.alwaysTemplate)
        patternView.contentMode = .scaleAspectFill
        patternMaskView.image = pattern
        patternMaskView.contentMode = .scaleAspectFill
        addSubview(patternView)
        apply()
    }

    required init?(coder: NSCoder) { fatalError() }

    public func setTheme(_ theme: Theme.Wallpaper) {
        self.theme = theme
        renderedSize = .zero
        apply()
        setNeedsLayout()
    }

    private func apply() {
        gradientView.isHidden = theme.plainColor != nil
        if let plainColor = theme.plainColor {
            backgroundColor = plainColor
            patternView.isHidden = true
        } else if theme.intensity >= 0 {
            backgroundColor = .clear
            gradientView.alpha = 1
            gradientView.mask = nil
            patternView.isHidden = !showsPattern
            patternView.tintColor = .black
            patternView.alpha = theme.intensity
            patternView.layer.compositingFilter = "softLightBlendMode"
        } else {
            backgroundColor = .black
            gradientView.alpha = abs(theme.intensity)
            gradientView.mask = patternMaskView
            gradientView.isHidden = !showsPattern
            patternView.isHidden = true
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientView.frame = bounds
        patternView.frame = bounds
        patternMaskView.frame = gradientView.bounds
        if renderedSize != bounds.size, bounds.width > 0 {
            renderedSize = bounds.size
            let size = Self.gradientImageSize(for: bounds.size)
            let positions = Self.positions(phase: phase)
            gradientView.image = Self.generateGradient(size: size, colors: theme.colors, positions: positions)
            dimmedGradientImage = Self.generateGradient(size: size, colors: theme.colors, positions: positions, saturation: 1.7)
        }
    }

    /// Telegram rotates the gradient one phase on every sent message (0.5s, 30 fps keyframes).
    public func animatePhase(duration: TimeInterval = 0.5) {
        guard bounds.width > 0 else { return }
        let from = Self.positions(phase: phase)
        phase = (phase + 1) % 8
        let to = Self.positions(phase: phase)
        let size = Self.gradientImageSize(for: bounds.size)
        let frameCount = max(2, Int(duration * 30))
        var images: [CGImage] = []
        for i in 0 ..< frameCount {
            // ease-in-out between the two phases
            let t = CGFloat(i) / CGFloat(frameCount - 1)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let positions = zip(from, to).map { CGPoint(x: $0.x + ($1.x - $0.x) * e, y: $0.y + ($1.y - $0.y) * e) }
            if let image = Self.generateGradient(size: size, colors: theme.colors, positions: positions).cgImage { images.append(image) }
        }
        gradientView.image = UIImage(cgImage: images.last!)
        dimmedGradientImage = Self.generateGradient(size: size, colors: theme.colors, positions: to, saturation: 1.7)
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = images
        animation.duration = duration
        animation.calculationMode = .linear
        gradientView.layer.add(animation, forKey: "contents")
    }

    // MARK: Gradient (port of SoftwareGradientBackground.generateGradient)

    private static let basePositions: [CGPoint] = [
        CGPoint(x: 0.80, y: 0.10), CGPoint(x: 0.60, y: 0.20), CGPoint(x: 0.35, y: 0.25), CGPoint(x: 0.25, y: 0.60),
        CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.40, y: 0.80), CGPoint(x: 0.65, y: 0.75), CGPoint(x: 0.75, y: 0.40),
    ]

    static func positions(phase: Int) -> [CGPoint] {
        var shifted = basePositions
        for _ in 0 ..< (phase % 8) { shifted.append(shifted.removeFirst()) }
        return stride(from: 0, to: shifted.count, by: 2).map { shifted[$0] }
    }

    /// size.fitted(80 × 80).integralFloor — the gradient is rendered tiny and stretched.
    static func gradientImageSize(for size: CGSize) -> CGSize {
        let scale = min(80 / size.width, 80 / size.height)
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }

    static func generateGradient(size: CGSize, colors inputColors: [UIColor], positions: [CGPoint], saturation: CGFloat = 1) -> UIImage {
        let colors = inputColors.count == 1 ? Array(repeating: inputColors[0], count: 3) : inputColors
        let width = Int(size.width), height = Int(size.height)
        var rgb: [Float] = []
        for color in colors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            rgb += [Float(r), Float(g), Float(b)]
        }
        let pos: [Float] = positions.flatMap { [Float($0.x), Float(1 - $0.y)] }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0 ..< height {
            let directY = Float(y) / Float(height)
            let cy = directY - 0.5
            for x in 0 ..< width {
                let directX = Float(x) / Float(width)
                let cx = directX - 0.5
                let centerDistance = sqrt(cx * cx + cy * cy)
                let swirl = 0.35 * centerDistance
                let theta = swirl * swirl * 0.8 * 8
                let s = sin(theta), c = cos(theta)
                let px = max(0, min(1, 0.5 + cx * c - cy * s))
                let py = max(0, min(1, 0.5 + cx * s + cy * c))

                var sum: Float = 0, r: Float = 0, g: Float = 0, b: Float = 0
                for i in 0 ..< colors.count {
                    let dx = px - pos[i * 2], dy = py - pos[i * 2 + 1]
                    var d = max(0, 0.92 - sqrt(dx * dx + dy * dy))
                    d = d * d * d
                    sum += d
                    r += d * rgb[i * 3]; g += d * rgb[i * 3 + 1]; b += d * rgb[i * 3 + 2]
                }
                sum = max(sum, 0.00001)
                let o = y * bytesPerRow + x * 4
                pixels[o] = UInt8(min(r / sum * 255, 255))
                pixels[o + 1] = UInt8(min(g / sum * 255, 255))
                pixels[o + 2] = UInt8(min(b / sum * 255, 255))
                pixels[o + 3] = 255
            }
        }
        if abs(saturation - 1) > .ulpOfOne { adjustSaturation(&pixels, width: width, height: height, saturation: saturation) }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image)
    }

    /// adjustSaturationInContext: the standard luminance-preserving saturation matrix.
    private static func adjustSaturation(_ pixels: inout [UInt8], width: Int, height: Int, saturation s: CGFloat) {
        let rw: CGFloat = 0.3086, gw: CGFloat = 0.6094, bw: CGFloat = 0.0820
        let m: [[CGFloat]] = [
            [(1 - s) * rw + s, (1 - s) * gw, (1 - s) * bw],
            [(1 - s) * rw, (1 - s) * gw + s, (1 - s) * bw],
            [(1 - s) * rw, (1 - s) * gw, (1 - s) * bw + s],
        ]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]), g = CGFloat(pixels[i + 1]), b = CGFloat(pixels[i + 2])
            for k in 0 ..< 3 {
                let v = m[k][0] * r + m[k][1] * g + m[k][2] * b
                pixels[i + k] = UInt8(max(0, min(255, v)))
            }
        }
    }
}
