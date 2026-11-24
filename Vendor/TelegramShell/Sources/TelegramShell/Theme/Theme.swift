import UIKit

/// Telegram's default themes for new installs: Day Classic (light) and Night (dark, follows the system).
/// Source: Telegram-iOS submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift (defaultSettings),
///         submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift (day == false),
///         submodules/TelegramPresentationData/Sources/DefaultDarkPresentationTheme.swift.
public struct Theme: Sendable {
    public struct Bubble: Sendable {
        /// One color, or a vertical screen-space gradient (Night outgoing).
        public var fill: [UIColor]
        public var highlightedFill: UIColor
        public var stroke: UIColor
        public var text: UIColor
        public var secondaryText: UIColor
        public var link: UIColor
        public var accent: UIColor
        public var checkmark: UIColor
    }

    public struct Wallpaper: Sendable {
        /// 4-color gradient (SoftwareGradientBackground).
        public var colors: [UIColor]
        /// Pattern intensity in 0…1. Negative = inverted pattern on black (Night).
        public var intensity: CGFloat
        /// A single-color wallpaper (Telegram's `.color`): no gradient, no pattern. Several rules follow it:
        /// the edge effect is stronger (ChatControllerNode: 0.85), photos sit 1pt inside their bubble
        /// (ChatMessageMediaBubbleContentNode).
        public var plainColor: UIColor?

        public init(colors: [UIColor], intensity: CGFloat, plainColor: UIColor? = nil) {
            self.colors = colors
            self.intensity = intensity
            self.plainColor = plainColor
        }
    }

    public var isDark: Bool
    public var accent: UIColor

    public var incoming: Bubble
    public var outgoing: Bubble
    public var wallpaper: Wallpaper

    // Service messages (date pills)
    public var serviceText: UIColor
    public var serviceDim: UIColor

    // Navigation / glass controls
    public var controlColor: UIColor          // glass buttons and chat title (inputPanel.panelControlColor)
    public var secondaryControlColor: UIColor // subtitle when not "online" (inputPanel.inputControlColor)
    public var onlineColor: UIColor
    public var glassTint: UIColor             // GlassBackgroundComponent `.panel` tint

    // Input panel
    public var inputPlaceholder: UIColor
    public var inputText: UIColor
    public var inputControl: UIColor          // icons inside the text field
    public var sendFill: UIColor
    public var sendIcon: UIColor

    // Chat list
    public var listBackground: UIColor
    public var listSeparator: UIColor
    public var listTitle: UIColor
    public var listText: UIColor
    public var listCheck: UIColor
    public var badgeFill: UIColor
    public var badgeText: UIColor
    public var badgeMutedFill: UIColor
    public var pinnedBackground: UIColor

    public static let dayClassic = Theme(
        isDark: false,
        accent: UIColor(rgb: 0x0088ff),
        incoming: Bubble(
            fill: [UIColor(rgb: 0xffffff)],
            highlightedFill: UIColor(rgb: 0xd9f4ff),
            stroke: UIColor(white: 0, alpha: 0.2),
            text: UIColor(rgb: 0x000000),
            secondaryText: UIColor(rgb: 0x77828c),
            link: UIColor(rgb: 0x004bad),
            accent: UIColor(rgb: 0x0088ff),
            checkmark: UIColor(rgb: 0x0088ff)
        ),
        outgoing: Bubble(
            fill: [UIColor(rgb: 0xe1ffc7)],
            highlightedFill: UIColor(rgb: 0xbaff93),
            stroke: UIColor(white: 0, alpha: 0.2),
            text: UIColor(rgb: 0x000000),
            secondaryText: UIColor(rgb: 0x008c09, alpha: 0.8),
            link: UIColor(rgb: 0x004bad),
            accent: UIColor(rgb: 0x00a700),
            checkmark: UIColor(rgb: 0x19c700)
        ),
        wallpaper: Wallpaper(
            colors: [UIColor(rgb: 0xdbddbb), UIColor(rgb: 0x6ba587), UIColor(rgb: 0xd5d88d), UIColor(rgb: 0x88b884)],
            intensity: 0.5
        ),
        serviceText: .white,
        serviceDim: UIColor(white: 0, alpha: 0.2),
        controlColor: .black,
        secondaryControlColor: UIColor(white: 0, alpha: 0.5),
        onlineColor: UIColor(rgb: 0x0088ff),
        glassTint: UIColor(white: 1, alpha: 0.1),
        inputPlaceholder: UIColor(white: 0, alpha: 0.4),
        inputText: .black,
        inputControl: UIColor(white: 0, alpha: 0.5),
        sendFill: UIColor(rgb: 0x0088ff), // systemBlue in light (see the dark theme)
        sendIcon: .white,
        listBackground: .white,
        listSeparator: UIColor(rgb: 0xc8c7cc),
        listTitle: .black,
        listText: UIColor(rgb: 0x8e8e93),
        listCheck: UIColor(rgb: 0x21c004),
        badgeFill: UIColor(rgb: 0x0088ff),
        badgeText: .white,
        badgeMutedFill: UIColor(rgb: 0xb6b6bb),
        pinnedBackground: UIColor(rgb: 0xf7f7f7)
    )

    public static let night = Theme(
        isDark: true,
        accent: .white,
        incoming: Bubble(
            fill: [UIColor(rgb: 0x1d1d1d, alpha: 0.9)],
            highlightedFill: UIColor(white: 1, alpha: 0.35),
            stroke: .clear,
            text: .white,
            secondaryText: UIColor(white: 1, alpha: 0.5),
            link: .white,
            accent: .white,
            checkmark: .white
        ),
        outgoing: Bubble(
            fill: [UIColor(rgb: 0x61bcf9), UIColor(rgb: 0x0088ff)],
            highlightedFill: UIColor(white: 1, alpha: 0.35),
            stroke: .clear,
            text: .white,
            secondaryText: UIColor(white: 1, alpha: 0.5),
            link: .white,
            accent: .white,
            checkmark: .white
        ),
        wallpaper: Wallpaper(
            colors: [UIColor(rgb: 0x598bf6), UIColor(rgb: 0x7a5eef), UIColor(rgb: 0xd67cff), UIColor(rgb: 0xf38b58)],
            intensity: -0.34
        ),
        serviceText: .white,
        serviceDim: UIColor(white: 0, alpha: 0.2),
        controlColor: .white,
        secondaryControlColor: UIColor(white: 1, alpha: 0.5),
        onlineColor: .white,
        glassTint: UIColor(white: 1, alpha: 0.025),
        inputPlaceholder: UIColor(white: 1, alpha: 0.48),
        inputText: .white,
        inputControl: UIColor(white: 1, alpha: 0.5),
        // The send capsule inside the field is blue glass with a white glyph in both themes: UIColor.systemBlue for the
        // built-in blues and black/white accents (ChatTextInputActionButtonsNode.swift, the non-bubble-mode path;
        // systemBlue resolves to 0091FF in dark). The white-on-black capsule is the fork's "bubble mode", not the App Store look.
        sendFill: UIColor(rgb: 0x0091ff),
        sendIcon: .white,
        listBackground: .black,
        listSeparator: UIColor(rgb: 0x545458, alpha: 0.55),
        listTitle: .white,
        listText: UIColor(rgb: 0x8d8e93),
        listCheck: .white,
        badgeFill: .white,
        badgeText: .black,
        badgeMutedFill: UIColor(rgb: 0x666666),
        pinnedBackground: UIColor(rgb: 0x1c1c1d)
    )

    /// Night with a plain black wallpaper instead of the patterned one: a quiet background for demos.
    public static let nightPlain: Theme = {
        var theme = night
        theme.wallpaper.plainColor = .black
        return theme
    }()

    /// The theme used in dark appearance. A concept can switch it to `nightPlain` before the UI loads.
    nonisolated(unsafe) public static var dark: Theme = .night

    public static func current(for traits: UITraitCollection) -> Theme {
        traits.userInterfaceStyle == .dark ? dark : .dayClassic
    }
}

/// Metrics at the default text size (17pt, "regular").
/// Source: ChatMessageItemCommon.swift (compact layout constants), ChatMessageDateAndStatusNode.swift,
///         PresentationThemeEssentialGraphics.swift, ChatMessageDateHeader.swift.
public enum Metrics {
    public static let pixel: CGFloat = 1 / 3

    // Bubbles
    public static let maxCornerRadius: CGFloat = 16
    public static let minCornerRadius: CGFloat = 8
    public static let bubbleEdgeInset: CGFloat = 3
    public static let tailWidth: CGFloat = 6
    public static let textInsets = UIEdgeInsets(top: 6 + pixel, left: 11, bottom: 6 - pixel, right: 11)
    public static let minBubbleSize = CGSize(width: 40, height: 35)
    public static let mergedSpacing: CGFloat = 2
    public static let groupSpacing: CGFloat = 2 * (2 + pixel) + 2
    /// maximumWidthFill(compactInset: 36, boundary: 500, freeFactor: 0.85)
    public static func maxBubbleWidth(for width: CGFloat) -> CGFloat {
        width <= 500 ? width - 36 : floor(width * 0.85)
    }

    // Text
    public static let messageFont = UIFont.systemFont(ofSize: 17)
    public static let lineSpacingFactor: CGFloat = 0.12
    public static let dateFont = UIFont.systemFont(ofSize: 11)
    public static let checkWidth: CGFloat = 11
    public static let checkOffset: CGFloat = 6
    public static let statusWidth: CGFloat = 13

    // Photo messages (ChatMessageItemLayoutConstants.compact.image; ChatMessageDateAndStatusNode, image types)
    public static let imageInset: CGFloat = 2
    public static let imageCornerRadius: CGFloat = 15
    public static let imageMaxSize = CGSize(width: 300, height: 380)
    public static let imageMinSize = CGSize(width: 170, height: 74)
    public static let imageStatusInset: CGFloat = 6
    public static let imageStatusPadding = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
    /// chat.message.mediaDateAndStatusFillColor / TextColor.
    public static let imageStatusFill = UIColor(white: 0, alpha: 0.3)

    // Date header
    public static let dateHeaderHeight: CGFloat = 34
    public static let datePillHeight: CGFloat = 22
    public static let datePillFont = UIFont.systemFont(ofSize: 13, weight: .medium)

    // Glass navigation bar (NavigationBarNode, ChatTitleComponent, ChatAvatarNavigationNode)
    public static let navRowHeight: CGFloat = 44
    public static let navSideInset: CGFloat = 16
    public static let navTopOffset: CGFloat = 2 + 8
    public static let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    public static let subtitleFont = UIFont.systemFont(ofSize: 12)
    public static let navAvatarSize: CGFloat = 38

    // Input panel (ChatTextInputPanelNode, ChatTextInputActionButtonsNode)
    public static let inputHeight: CGFloat = 40
    public static let inputSideInset: CGFloat = 8
    public static let inputButtonGap: CGFloat = 6
    public static let inputBottomGap: CGFloat = 8
    public static let inputFont = UIFont.systemFont(ofSize: 17)
}
