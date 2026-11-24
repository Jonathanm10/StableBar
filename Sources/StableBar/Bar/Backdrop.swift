import SwiftUI

extension EnvironmentValues {
    /// With `bar.textFollowsBackground`, the color behind a view of the bar: the backgrounds of the bar, the group and
    /// the widget over the wallpaper, which counts as black or white as the display's menu bar is dark or light.
    @Entry var backdrop: UInt32?
}

/// Adds `fill` to the backdrop of the content. Given the `text` drawn there, the content keeps the bar's appearance
/// unless that text reads below 3:1 on the backdrop and reads better in the other appearance.
struct FollowsBackground: ViewModifier {
    let fill: BackgroundFill?
    var text: HexColor?
    @Environment(\.backdrop) private var backdrop
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let color = backdrop.map { backdrop in
            fill.map { blend(colorScheme == .dark ? $0.firstColor.dark : $0.firstColor.light, over: backdrop) } ?? backdrop
        }
        content
            .environment(\.colorScheme, color.flatMap { color in text.map { readableScheme($0, on: color, in: colorScheme) } } ?? colorScheme)
            .environment(\.backdrop, color)
    }
}

func readableScheme(_ text: HexColor, on backdrop: UInt32, in scheme: ColorScheme) -> ColorScheme {
    let other: ColorScheme = scheme == .dark ? .light : .dark
    let contrast = { (scheme: ColorScheme) in contrastRatio(blend(scheme == .dark ? text.dark : text.light, over: backdrop), backdrop) }
    return contrast(scheme) < 3 && contrast(other) > contrast(scheme) ? other : scheme
}

/// `rgba` drawn over the opaque `backdrop`.
func blend(_ rgba: UInt32, over backdrop: UInt32) -> UInt32 {
    let alpha = Double(rgba & 0xff) / 255
    return [24, 16, 8].reduce(UInt32(0xff)) { color, shift in
        let channel = alpha * Double((rgba >> UInt32(shift)) & 0xff) + (1 - alpha) * Double((backdrop >> UInt32(shift)) & 0xff)
        return color | UInt32(channel.rounded()) << UInt32(shift)
    }
}

/// WCAG contrast ratio of two opaque colors.
func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
    let (la, lb) = (luminance(a), luminance(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// WCAG relative luminance of an RGBA color.
func luminance(_ rgba: UInt32) -> Double {
    let channels = [24, 16, 8].map { shift in
        let value = Double((rgba >> UInt32(shift)) & 0xff) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}
