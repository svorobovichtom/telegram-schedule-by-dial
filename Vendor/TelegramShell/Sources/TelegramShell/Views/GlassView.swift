import UIKit

/// Telegram's glass capsule: on iOS 26+ a UIGlassEffect view with the `.panel` tint.
/// Source: submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift
public final class GlassView: UIView {
    public let effectView: UIVisualEffectView
    /// Put content here (it sits on top of the glass and gets its vibrancy-free rendering).
    public var contentView: UIView { effectView.contentView }

    public var tint: UIColor? { didSet { updateEffect() } }
    /// nil: a capsule (half the height). Set for shapes that keep their radius as they grow, like the text field,
    /// which stays at radius 20 when it takes several lines (ChatTextInputPanelNode.swift:3349).
    public var cornerRadius: CGFloat? { didSet { setNeedsLayout() } }
    public var isInteractive: Bool { didSet { updateEffect() } }

    public init(tint: UIColor? = nil, interactive: Bool = false) {
        self.tint = tint
        self.isInteractive = interactive
        effectView = UIVisualEffectView(effect: nil)
        super.init(frame: .zero)
        addSubview(effectView)
        updateEffect()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateEffect() {
        let effect = UIGlassEffect(style: .regular)
        effect.tintColor = tint
        effect.isInteractive = isInteractive
        effectView.effect = effect
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        if let cornerRadius {
            effectView.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
        } else {
            effectView.cornerConfiguration = .capsule()
        }
    }
}

/// A round glass button with a template icon, like the attach and mic buttons.
public final class GlassButton: UIControl {
    public let glass: GlassView
    public let iconView = UIImageView()

    public init(icon: UIImage?, tint: UIColor? = nil) {
        glass = GlassView(tint: tint, interactive: true)
        super.init(frame: .zero)
        glass.isUserInteractionEnabled = false
        addSubview(glass)
        iconView.image = icon
        iconView.contentMode = .center
        glass.contentView.addSubview(iconView)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        // contentView fills the glass, which fills us; don't read its bounds before it is laid out.
        iconView.frame = CGRect(origin: .zero, size: bounds.size)
    }
}
