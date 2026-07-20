import SwiftUI
import UIKit

/// Central color language for the app. Green tonal palette shared with the
/// sibling apps (BirdApp / RadioApp). Use these instead of hard-coded RGB values.
enum AppTheme {
    /// Builds a color that resolves differently in light and dark mode.
    /// Row tints have to be defined this way: a fixed pastel fill is invisible
    /// behind white text once the system flips `.primary` in dark mode.
    private static func adaptive(light: (Double, Double, Double),
                                 dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    // MARK: - Brand greens (matched to the BirdApp icon gradient & accent)
    static let greenDeep   = Color(red: 0.04, green: 0.44, blue: 0.33)   // #0B6F53 (icon bottom)
    static let greenDark   = Color(red: 0.10, green: 0.50, blue: 0.37)   // #198060
    static let green       = Color(red: 0.137, green: 0.620, blue: 0.482) // accent (BirdApp)
    static let greenMid    = Color(red: 0.169, green: 0.745, blue: 0.573) // accent dark (BirdApp)
    static let greenBright = Color(red: 0.22, green: 0.82, blue: 0.58)   // #37D094 (icon top)
    /// Light tint for fills — a deep, desaturated green in dark mode so white text reads.
    static let greenSoft = adaptive(light: (0.90, 0.96, 0.93), dark: (0.08, 0.20, 0.16))

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

    // MARK: - Row tints (Sol·Luna calendar & tides)
    // Same hue family in both modes: pale in light, deep in dark.

    /// Pleamar / high tide — cool blue.
    static let rowCool = adaptive(light: (0.94, 0.97, 1.00), dark: (0.09, 0.15, 0.24))
    /// Bajamar, luna llena / low tide, full moon — warm sand.
    static let rowWarm = adaptive(light: (1.00, 0.98, 0.88), dark: (0.20, 0.17, 0.08))
    /// Luna nueva — cool lilac.
    static let rowLilac = adaptive(light: (0.93, 0.94, 0.99), dark: (0.13, 0.14, 0.22))
    /// Today's astronomical event — amber highlight.
    static let rowToday = adaptive(light: (1.00, 0.95, 0.75), dark: (0.26, 0.21, 0.06))
    /// Neutral filler for past / distant rows.
    static let rowNeutral = Color(.secondarySystemBackground)
}
