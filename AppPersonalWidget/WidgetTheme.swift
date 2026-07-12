import SwiftUI

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

/// Temperature → colour, for the Netatmo widget's "colour by temperature" background.
///
/// Anchored on how the temperature *feels* rather than on an even split: freezing is deep
/// blue, the comfortable teens are green, and it warms through amber and red into violet at
/// the 40-45° end (violet reads as "off the scale" — hotter than plain red can say).
/// Colours are deliberately dark: the widget draws white text on top and must stay legible.
enum TempPalette {
    // Saturated on purpose: a first pass with muted stops interpolated into mud (28° came
    // out an ochre brown). These stay vivid through the mid-range, where the temperature
    // actually spends most of the year.
    private static let stops: [(t: Double, c: (r: Double, g: Double, b: Double))] = [
        (-10, (0.10, 0.13, 0.42)),   // hielo — azul noche
        (  0, (0.11, 0.32, 0.78)),   // cero — azul intenso
        ( 10, (0.08, 0.58, 0.72)),   // fresco — turquesa
        ( 18, (0.12, 0.66, 0.45)),   // templado — verde (la casa)
        ( 25, (0.95, 0.66, 0.15)),   // cálido — dorado
        ( 32, (0.94, 0.40, 0.10)),   // calor — naranja
        ( 38, (0.87, 0.16, 0.22)),   // mucho calor — rojo
        ( 45, (0.58, 0.10, 0.58)),   // extremo — violeta
    ]

    /// Linear interpolation between the two surrounding stops; clamps outside the range.
    static func color(for temp: Double) -> Color {
        guard let first = stops.first, let last = stops.last else { return .gray }
        if temp <= first.t { return Color(red: first.c.r, green: first.c.g, blue: first.c.b) }
        if temp >= last.t  { return Color(red: last.c.r,  green: last.c.g,  blue: last.c.b) }
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            guard temp >= a.t, temp <= b.t else { continue }
            let f = (temp - a.t) / (b.t - a.t)
            return Color(red:   a.c.r + (b.c.r - a.c.r) * f,
                         green: a.c.g + (b.c.g - a.c.g) * f,
                         blue:  a.c.b + (b.c.b - a.c.b) * f)
        }
        return .gray
    }

    /// Background gradient for a reading: the temperature's colour, lit from the top.
    /// Falls back to the app's green when there's no reading at all.
    static func gradient(for temp: Double?) -> LinearGradient {
        guard let temp else { return WidgetTheme.heroGradient }
        let base = color(for: temp)
        // Keep the top at full strength and only deepen the bottom: darkening both ends
        // was what turned the warm colours to mud.
        return LinearGradient(colors: [base, base.mix(with: .black, by: 0.30)],
                              startPoint: .top, endPoint: .bottom)
    }
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
