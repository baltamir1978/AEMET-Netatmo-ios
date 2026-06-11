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
