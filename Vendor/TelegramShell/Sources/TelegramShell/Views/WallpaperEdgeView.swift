import UIKit

/// Telegram's wallpaper edge effect: at the top (under the header) and bottom (under the input panel) a copy of the
/// wallpaper covers the content through a gradient mask, so messages fade into the background instead of showing
/// under the glass. Source: submodules/WallpaperBackgroundNode/Sources/WallpaperEdgeEffectNodeImpl.swift,
/// ChatControllerNode.swift (top: down to header + 34, 80pt edge; bottom: from input − 20, 60pt edge; alpha 0.75 for
/// gradient wallpapers) and EdgeEffectView.generateEdgeGradient (the alpha curve below).
/// Telegram also adds a variable blur at the top through a private filter; this is the color part only.
public final class WallpaperEdgeView: UIView {
    public enum Edge { case top, bottom }

    public let edge: Edge
    /// A second wallpaper kept in sync with the chat's (theme and phase), aligned to the screen.
    public let wallpaper: WallpaperView
    /// The mask: a solid part on the outer side and the fade next to the content.
    private let edgeMask = UIView()
    private let maskSolid = UIView()
    private let maskFade = UIImageView()
    private let container = UIView()
    private var edgeSize: CGFloat = 0

    public init(edge: Edge, theme: Theme.Wallpaper) {
        self.edge = edge
        wallpaper = WallpaperView(theme: theme)
        wallpaper.showsPattern = false
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        container.addSubview(wallpaper)
        maskSolid.backgroundColor = .black
        maskFade.contentMode = .scaleToFill
        edgeMask.addSubview(maskSolid)
        edgeMask.addSubview(maskFade)
        container.mask = edgeMask
        addSubview(container)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `screen`: the chat's bounds (the wallpaper is laid out in it); `edgeSize`: length of the fade.
    public func update(frame: CGRect, screen: CGRect, edgeSize: CGFloat, alpha: CGFloat = 0.75) {
        self.frame = frame
        container.frame = bounds
        container.alpha = alpha
        wallpaper.frame = screen.offsetBy(dx: -frame.minX, dy: -frame.minY)
        if self.edgeSize != edgeSize {
            self.edgeSize = edgeSize
            maskFade.image = Self.gradient(height: edgeSize, inverted: edge == .bottom)
        }
        edgeMask.frame = bounds
        let fade = min(edgeSize, bounds.height)
        if edge == .top {
            maskSolid.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - fade)
            maskFade.frame = CGRect(x: 0, y: bounds.height - fade, width: bounds.width, height: fade)
        } else {
            maskFade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fade)
            maskSolid.frame = CGRect(x: 0, y: fade, width: bounds.width, height: bounds.height - fade)
        }
    }

    /// The fade itself: opaque on the outer side, clear towards the content.
    static func gradient(height: CGFloat, inverted: Bool) -> UIImage {
        let norm = alphas.max() ?? 1
        let colors = alphas.map { UIColor(white: 0, alpha: $0 / norm).cgColor } as CFArray
        var locations = locations
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: &locations)!
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: height)).image { context in
            let start = inverted ? CGPoint(x: 0, y: height) : .zero
            let end = inverted ? .zero : CGPoint(x: 0, y: height)
            context.cgContext.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
    }

    private static let alphas: [CGFloat] = [
        0.8470588235294118, 0.8431372549019608, 0.8392156862745098, 0.8352941176470589, 0.8313725490196078, 0.8274509803921568,
        0.8235294117647058, 0.8196078431372549, 0.8156862745098039, 0.8117647058823529, 0.807843137254902, 0.803921568627451,
        0.8, 0.7960784313725491, 0.792156862745098, 0.788235294117647, 0.7843137254901961, 0.7803921568627451,
        0.7764705882352941, 0.7725490196078432, 0.7686274509803921, 0.7647058823529411, 0.7607843137254902, 0.7568627450980392,
        0.7529411764705882, 0.7490196078431373, 0.7450980392156863, 0.7411764705882353, 0.7372549019607844, 0.7333333333333334,
        0.7294117647058824, 0.7254901960784313, 0.7215686274509804, 0.7176470588235294, 0.7137254901960784, 0.7098039215686274,
        0.7019607843137254, 0.6941176470588235, 0.6862745098039216, 0.6784313725490196, 0.6705882352941177, 0.6588235294117647,
        0.6509803921568628, 0.6431372549019607, 0.6313725490196078, 0.6235294117647059, 0.615686274509804, 0.603921568627451,
        0.596078431372549, 0.5882352941176471, 0.5764705882352941, 0.5647058823529412, 0.5529411764705883, 0.5411764705882354,
        0.5294117647058824, 0.5176470588235293, 0.5058823529411764, 0.49411764705882355, 0.4862745098039216, 0.4745098039215686,
        0.4627450980392157, 0.4549019607843138, 0.44313725490196076, 0.43137254901960786, 0.41960784313725485, 0.4117647058823529,
        0.4, 0.388235294117647, 0.3764705882352941, 0.3647058823529412, 0.3529411764705882, 0.3411764705882353,
        0.3294117647058824, 0.3176470588235294, 0.3058823529411765, 0.2941176470588235, 0.2823529411764706, 0.2705882352941177,
        0.2588235294117647, 0.2431372549019608, 0.2313725490196078, 0.21568627450980393, 0.19999999999999996, 0.18039215686274512,
        0.16078431372549018, 0.14117647058823535, 0.11764705882352944, 0.09019607843137256, 0.04705882352941182, 0.0,
    ]

    private static let locations: [CGFloat] = [
        0.0, 0.020905923344947737, 0.059233449477351915, 0.08710801393728224, 0.10801393728222997, 0.12195121951219512,
        0.13240418118466898, 0.14285714285714285, 0.15331010452961671, 0.1602787456445993, 0.17073170731707318, 0.18118466898954705,
        0.1916376306620209, 0.20209059233449478, 0.20905923344947736, 0.21254355400696864, 0.21951219512195122, 0.2264808362369338,
        0.23344947735191637, 0.23693379790940766, 0.24390243902439024, 0.24738675958188153, 0.25435540069686413, 0.2578397212543554,
        0.2613240418118467, 0.2682926829268293, 0.27177700348432055, 0.27526132404181186, 0.28222996515679444, 0.2857142857142857,
        0.289198606271777, 0.2926829268292683, 0.2961672473867596, 0.29965156794425085, 0.30313588850174217, 0.30662020905923343,
        0.313588850174216, 0.3205574912891986, 0.32752613240418116, 0.3344947735191638, 0.34146341463414637, 0.34843205574912894,
        0.3554006968641115, 0.3623693379790941, 0.3693379790940767, 0.37630662020905925, 0.3797909407665505, 0.3867595818815331,
        0.39372822299651566, 0.397212543554007, 0.40418118466898956, 0.41114982578397213, 0.4181184668989547, 0.4250871080139373,
        0.43205574912891986, 0.43902439024390244, 0.445993031358885, 0.4529616724738676, 0.4564459930313589, 0.4634146341463415,
        0.47038327526132406, 0.4738675958188153, 0.4808362369337979, 0.4878048780487805, 0.49477351916376305, 0.49825783972125437,
        0.5052264808362369, 0.5121951219512195, 0.519163763066202, 0.5261324041811847, 0.5331010452961672, 0.5400696864111498,
        0.5470383275261324, 0.554006968641115, 0.5609756097560976, 0.5679442508710801, 0.5749128919860628, 0.5818815331010453,
        0.5888501742160279, 0.5993031358885017, 0.6062717770034843, 0.6167247386759582, 0.627177700348432, 0.6411149825783972,
        0.6585365853658537, 0.6759581881533101, 0.6968641114982579, 0.7282229965156795, 0.7909407665505227, 1.0,
    ]
}
