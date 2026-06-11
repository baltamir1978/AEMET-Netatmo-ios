import SwiftUI

/// Central color language for the app. Green tonal palette shared with the
/// sibling apps (BirdApp / RadioApp). Use these instead of hard-coded RGB values.
enum AppTheme {
    // MARK: - Brand greens (matched to the BirdApp icon gradient & accent)
    static let greenDeep   = Color(red: 0.04, green: 0.44, blue: 0.33)   // #0B6F53 (icon bottom)
    static let greenDark   = Color(red: 0.10, green: 0.50, blue: 0.37)   // #198060
    static let green       = Color(red: 0.137, green: 0.620, blue: 0.482) // accent (BirdApp)
    static let greenMid    = Color(red: 0.169, green: 0.745, blue: 0.573) // accent dark (BirdApp)
    static let greenBright = Color(red: 0.22, green: 0.82, blue: 0.58)   // #37D094 (icon top)
    static let greenSoft   = Color(red: 0.90, green: 0.96, blue: 0.93)   // light tint for fills

    /// Warm accent (the icon's sun) — for highlights like UV / sun-related data.
    static let sun = Color(red: 1.0, green: 0.77, blue: 0.24)            // #FFC53D

    /// Primary brand gradient (mirrors the icon: bright top → deep bottom).
    static let heroGradient = LinearGradient(
        colors: [greenBright, greenDeep],
        startPoint: .top, endPoint: .bottom
    )

    /// Softer gradient for secondary surfaces.
    static let softGradient = LinearGradient(
        colors: [greenMid, green],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Accent used for interactive elements (also mirrored in AccentColor asset).
    static let accent = green
}
