import UIKit

/// Round avatar: an image, or Telegram's gradient with initials.
/// Colors: Telegram-iOS submodules/AvatarNode/Sources/AvatarNode.swift `gradientColors`;
/// drawing: PeerAvatar.swift (gradient top → bottom, second color on top, white initials).
public final class AvatarView: UIView {
    public static let gradientColors: [[UIColor]] = [
        [UIColor(rgb: 0xff516a), UIColor(rgb: 0xff885e)],
        [UIColor(rgb: 0xffa85c), UIColor(rgb: 0xffcd6a)],
        [UIColor(rgb: 0x665fff), UIColor(rgb: 0x82b1ff)],
        [UIColor(rgb: 0x54cb68), UIColor(rgb: 0xa0de7e)],
        [UIColor(rgb: 0x4acccd), UIColor(rgb: 0x00fcfd)],
        [UIColor(rgb: 0x2a9ef1), UIColor(rgb: 0x72d5fd)],
        [UIColor(rgb: 0xd669ed), UIColor(rgb: 0xe0a2f3)],
    ]

    private let gradientLayer = CAGradientLayer()
    private let imageView = UIImageView()
    private let initialsLabel = UILabel()

    public var peer: DemoPeer? { didSet { update() } }

    public init(peer: DemoPeer? = nil) {
        self.peer = peer
        super.init(frame: .zero)
        clipsToBounds = true
        // Telegram draws locations [1, 0]: the first color at the bottom.
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        layer.addSublayer(gradientLayer)
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        addSubview(initialsLabel)
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        gradientLayer.frame = bounds
        imageView.frame = bounds
        initialsLabel.frame = bounds
        // Telegram: avatarFont(size: floor(diameter * 16 / 37)), semibold rounded-ish system font.
        initialsLabel.font = .systemFont(ofSize: floor(bounds.width * 16 / 37), weight: .semibold)
    }

    private func update() {
        guard let peer else { return }
        let colors = Self.gradientColors[abs(peer.colorIndex) % Self.gradientColors.count]
        gradientLayer.colors = colors.map(\.cgColor)
        initialsLabel.text = peer.initials
        if let name = peer.avatar, let image = UIImage(named: name) ?? UIImage(named: name, in: .module, with: nil) {
            imageView.image = image
            imageView.isHidden = false
        } else {
            imageView.isHidden = true
        }
    }
}

extension UIColor {
    public convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255, blue: CGFloat(rgb & 0xff) / 255, alpha: alpha)
    }

    /// 0xAARRGGBB, as Telegram's theme files write colors.
    public convenience init(argb: UInt32) {
        self.init(red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255, blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat((argb >> 24) & 0xff) / 255)
    }
}
