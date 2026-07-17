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

/// Temperature → colour, for the "colour by temperature" widget background.
///
/// Anchored on how the temperature *feels* rather than on an even split: freezing is deep
/// blue, the comfortable teens are green, and it warms through gold and orange into a deep
/// blood red at the 40-45° end (red keeps deepening rather than veering to violet — the heat
/// reading "off the scale" without changing hue family). Colours are deliberately dark: the
/// widget draws white text on top and must stay legible.
enum TempPalette {
    // 15 stops (was 8): the extra ones smooth the transitions and, crucially, add a
    // green-lime bridge at 21° that kills the olive mud the old green→gold jump produced.
    // Saturated on purpose through the mid-range, where the temperature spends most of the year.
    private static let stops: [(t: Double, c: (r: Double, g: Double, b: Double))] = [
        (-10, (0.10, 0.14, 0.40)),   // hielo — azul noche
        ( -5, (0.11, 0.24, 0.60)),   // muy frío — azul
        (  0, (0.12, 0.34, 0.80)),   // cero — azul intenso
        (  5, (0.10, 0.48, 0.78)),   // frío — azul-turquesa
        ( 10, (0.08, 0.60, 0.75)),   // fresco — turquesa
        ( 14, (0.10, 0.64, 0.60)),   // suave — verde-turquesa
        ( 18, (0.14, 0.68, 0.46)),   // templado — verde (la casa)
        ( 21, (0.58, 0.74, 0.22)),   // cálido — verde-lima (puente, sin oliva)
        ( 24, (0.92, 0.74, 0.12)),   // cálido — dorado
        ( 27, (0.97, 0.58, 0.10)),   // caluroso — ámbar
        ( 30, (0.98, 0.44, 0.10)),   // calor — naranja
        ( 34, (0.94, 0.26, 0.12)),   // mucho calor — naranja-rojo
        ( 38, (0.88, 0.14, 0.16)),   // sofocante — rojo
        ( 42, (0.72, 0.08, 0.12)),   // extremo — rojo profundo
        ( 45, (0.54, 0.04, 0.10)),   // extremo — rojo sangre
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
