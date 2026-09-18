import SwiftUI
import WidgetKit

/// Compact mirror of the app's `AppTheme` green palette, local to the widget target.
enum WidgetTheme {
    static let greenDeep   = Color(red: 0.04, green: 0.44, blue: 0.33)   // #0B6F53
    static let green       = Color(red: 0.137, green: 0.620, blue: 0.482)
    static let greenBright = Color(red: 0.22, green: 0.82, blue: 0.58)   // #37D094
    static let sun         = Color(red: 1.0, green: 0.77, blue: 0.24)    // #FFC53D

    static let heroGradient = LinearGradient(
        colors: [greenBright, greenDeep],
        startPoint: .top, endPoint: .bottom
    )
}

/// Temperature → colour, for the "colour by temperature" widget background.
///
/// The colours themselves live in `TempScale` (shared with the app, which offers the choice
/// in Ajustes); this adds the widget's side: the gradient under each reading and whether the
/// text on it should be white or dark ink. Every scale steps band by band, like a map legend,
/// instead of blending: the old single blend put muddy olive-mustards on the most common
/// readings of the year.
enum TempPalette {
    private typealias RGB = (r: Double, g: Double, b: Double)

    /// Text colour for the light bands (white doesn't read on pale or bright yellow grounds).
    static let darkInk = Color(red: 0x0B / 255, green: 0x22 / 255, blue: 0x36 / 255)
    private static let darkInkRGB: RGB = (0x0B / 255, 0x22 / 255, 0x36 / 255)

    /// Background gradient for a reading: the band's colour on top, the same hue a step
    /// darker at the bottom. Darkening by mixing in black is what turned the warm colours to
    /// mud, and would grey the pale ones. Falls back to the app's green with no reading.
    static func gradient(for temp: Double?, scale: TempScale = WidgetStore.loadTempScale()) -> LinearGradient {
        guard let temp else { return WidgetTheme.heroGradient }
        let top = rgb(for: temp, scale: scale)
        return LinearGradient(colors: [color(top), color(bottom(of: top))],
                              startPoint: .top, endPoint: .bottom)
    }

    /// Whether the widget's text should switch to `darkInk` on this reading's background:
    /// whichever of white and dark ink keeps more contrast at the worse end of the gradient.
    static func prefersDarkInk(for temp: Double?, scale: TempScale = WidgetStore.loadTempScale()) -> Bool {
        guard let temp else { return false }
        let top = rgb(for: temp, scale: scale), bot = bottom(of: top)
        let white: RGB = (1, 1, 1)
        let onWhite = min(contrast(white, top), contrast(white, bot))
        let onDark = min(contrast(darkInkRGB, top), contrast(darkInkRGB, bot))
        return onDark > onWhite
    }

    // MARK: Colour maths

    private static func rgb(for temp: Double, scale: TempScale) -> RGB {
        let hex = scale.color(for: temp)
        return (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func bottom(of c: RGB) -> RGB {
        let lab = oklab(c)
        return srgb((max(0, lab.0 - 0.10), lab.1, lab.2))
    }

    private static func color(_ c: RGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ v: Double) -> Double {
        let v = min(1, max(0, v))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static func oklab(_ c: RGB) -> (Double, Double, Double) {
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func srgb(_ lab: (Double, Double, Double)) -> RGB {
        let l = pow(lab.0 + 0.3963377774 * lab.1 + 0.2158037573 * lab.2, 3)
        let m = pow(lab.0 - 0.1055613458 * lab.1 - 0.0638541728 * lab.2, 3)
        let s = pow(lab.0 - 0.0894841775 * lab.1 - 1.2914855480 * lab.2, 3)
        return (gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    private static func contrast(_ a: RGB, _ b: RGB) -> Double {
        func lum(_ c: RGB) -> Double { 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b) }
        let x = lum(a), y = lum(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// Foreground colours for whatever the widget is drawn on. White and the bright accents on
/// the app's green and on dark temperature colours; dark ink and deeper accents on the light
/// ones. Tinted and clear home screens drop the background, so they always get the white set.
struct WidgetInk {
    let dark: Bool

    init(background: TempBackground, temperature: Double?, renderingMode: WidgetRenderingMode) {
        dark = renderingMode == .fullColor && background == .temperature
            && TempPalette.prefersDarkInk(for: temperature)
    }

    var text: Color { dark ? TempPalette.darkInk : .white }

    /// Secondary text at `opacity`. White can afford to fade on a dark ground; dark ink on a
    /// light one loses legibility much faster, so its text levels fade half as much. Values
    /// under 0.5 are hairlines (dividers, ring tracks) and are left as they are.
    func soft(_ opacity: Double) -> Color {
        guard dark, opacity >= 0.5 else { return text.opacity(opacity) }
        return text.opacity(1 - (1 - opacity) * 0.5)
    }

    /// Chance of rain. Deep blue rather than a dark green on light grounds: a green figure
    /// all but vanishes on the light greens some scales use.
    var rain: Color { dark ? Color(red: 0.05, green: 0.30, blue: 0.62) : WidgetTheme.greenBright }
    /// Pressure, good CO₂.
    var green: Color { dark ? Color(red: 0.03, green: 0.35, blue: 0.26) : WidgetTheme.greenBright }
    /// Humidity and rain rings.
    var cool: Color { dark ? Color(red: 0.12, green: 0.34, blue: 0.80) : .cyan }
    var amber: Color { dark ? Color(red: 0.66, green: 0.36, blue: 0.0) : WidgetTheme.sun }
    var red: Color { dark ? Color(red: 0.70, green: 0.10, blue: 0.12) : Color(red: 0.95, green: 0.45, blue: 0.40) }
    /// Min → max temperature bar.
    var rangeColors: [Color] { [cool, dark ? Color(red: 0.80, green: 0.30, blue: 0.04) : WidgetTheme.sun] }
}

/// Maps an AEMET sky code (e.g. "11n") to an SF Symbol + tint.
/// Mirrors `WeatherIconView` in the app.
enum SkyIcon {
    static func symbol(for code: String?) -> String {
        switch category(code) {
        case "clear":         return "sun.max.fill"
        case "clear-n":       return "moon.stars.fill"
        case "partly":        return "cloud.sun.fill"
        case "partly-n":      return "cloud.moon.fill"
        case "cloudy":        return "cloud.fill"
        case "high-clouds":   return "smoke.fill"
        case "rain":          return "cloud.rain.fill"
        case "shower":        return "cloud.drizzle.fill"
        case "thunder":       return "cloud.bolt.fill"
        case "thunder-rain":  return "cloud.bolt.rain.fill"
        case "snow":          return "cloud.snow.fill"
        case "light-snow":    return "cloud.sleet.fill"
        case "fog":           return "cloud.fog.fill"
        case "mist":          return "cloud.fog"
        default:              return "questionmark.circle"
        }
    }

    static func color(for code: String?) -> Color {
        switch category(code) {
        case "clear":                    return .yellow
        case "clear-n":                  return .indigo
        case "partly":                   return .orange
        case "partly-n":                 return .purple
        case "cloudy", "high-clouds":    return .gray
        case "rain", "shower":           return .blue
        case "thunder", "thunder-rain":  return .purple
        case "snow", "light-snow":       return .cyan
        case "fog", "mist":              return Color(.systemGray3)
        default:                         return .gray
        }
    }

    private static func category(_ code: String?) -> String {
        guard let code else { return "unknown" }
        let isNight = code.hasSuffix("n")
        let n = Int(code.filter { $0.isNumber }) ?? 0
        switch n {
        case 11: return isNight ? "clear-n" : "clear"
        case 12, 13: return isNight ? "partly-n" : "partly"
        case 14, 15, 16: return "cloudy"
        case 17: return "high-clouds"
        case 23...26: return "rain"
        case 33...36: return "snow"
        case 43...46: return "shower"
        case 51...54: return "thunder"
        case 61...64: return "thunder-rain"
        case 71...74: return "light-snow"
        case 81: return "fog"
        case 82, 83: return "mist"
        default: return "unknown"
        }
    }
}
