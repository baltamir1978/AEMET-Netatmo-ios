import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct SunMoonEntry: TimelineEntry {
    let date: Date
    let locationName: String
    let sunrise: String?
    let sunset: String?
    let moonrise: String?
    let moonset: String?
    let moonEmoji: String
    let moonPhase: String
    let illumination: Double      // 0…1
    let nextMoonLabel: String?    // e.g. "Luna llena"
    let nextMoonEmoji: String?
    let nextMoonWhen: String?     // e.g. "12 jun · 03:44"
}

// MARK: - Provider

struct SunMoonProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SunMoonEntry {
        entry(for: Date(), location: WidgetStore.selectedLocation())
    }

    func snapshot(for configuration: SelectLocationIntent, in context: Context) async -> SunMoonEntry {
        entry(for: Date(), location: resolveWidgetLocation(configuration))
    }

    func timeline(for configuration: SelectLocationIntent, in context: Context) async -> Timeline<SunMoonEntry> {
        let now = Date()
        let loc = resolveWidgetLocation(configuration)
        // One entry per hour for the next 12h so sunrise/sunset stay current.
        let entries = (0..<12).compactMap { h in
            Calendar.current.date(byAdding: .hour, value: h, to: now).map { entry(for: $0, location: loc) }
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for date: Date, location: SavedLocation) -> SunMoonEntry {
        let r = SunMoonService.shared.calculate(location: location.sunMoon, date: date)
        let next = MoonPhasesService.forZone(location.tz).nextPhases(from: date, count: 1).first
        return SunMoonEntry(
            date: date,
            locationName: r.location.name,
            sunrise: r.sun.sunrise,
            sunset: r.sun.sunset,
            moonrise: r.moon.moonrise,
            moonset: r.moon.moonset,
            moonEmoji: r.moon.emoji,
            moonPhase: r.moon.phase,
            illumination: r.moon.illumination,
            nextMoonLabel: next?.label,
            nextMoonEmoji: next?.emoji,
            nextMoonWhen: next.map { Self.format($0.datetime, tz: location.tz) }
        )
    }

    /// The next phase's clock time, in the location's own zone — a Portuguese city runs
    /// an hour behind, and everything else on the widget already reads local.
    private static func format(_ date: Date, tz: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "d MMM · HH:mm"
        return f.string(from: date)
    }
}

// MARK: - View

struct SunMoonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SunMoonEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            default:           medium
            }
        }
        // Tapping the widget opens the app's Sol·Luna tab.
        .widgetURL(WidgetDeepLink.url(WidgetDeepLink.cosmos))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(entry.locationName, systemImage: "location.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "sunrise.fill").foregroundStyle(WidgetTheme.sun)
                Text(entry.sunrise ?? "—").foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                Image(systemName: "sunset.fill").foregroundStyle(.orange)
                Text(entry.sunset ?? "—").foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(entry.moonEmoji).font(.title3)
                Text("\(Int((entry.illumination * 100).rounded()))%")
                    .foregroundStyle(.white)
            }
        }
        .font(.headline)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { WidgetTheme.heroGradient }
    }

    private func riseSetRow(_ symbol: String, _ tint: Color, _ value: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            Text(value ?? "—").foregroundStyle(.white)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(entry.locationName, systemImage: "location.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                riseSetRow("sunrise.fill", WidgetTheme.sun, entry.sunrise)
                riseSetRow("sunset.fill", .orange, entry.sunset)
                riseSetRow("moonrise.fill", .white.opacity(0.9), entry.moonrise)
                riseSetRow("moonset.fill", .white.opacity(0.7), entry.moonset)
            }
            .font(.subheadline.weight(.medium))

            Divider().overlay(.white.opacity(0.3))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.moonEmoji).font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.moonPhase).font(.caption).foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(Int((entry.illumination * 100).rounded()))% iluminada")
                            .font(.caption2).foregroundStyle(.white.opacity(0.75))
                    }
                }
                if let label = entry.nextMoonLabel, let when = entry.nextMoonWhen {
                    Divider().overlay(.white.opacity(0.2))
                    HStack(spacing: 6) {
                        Text(entry.nextMoonEmoji ?? "🌙")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.9))
                            Text(when).font(.caption2).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { WidgetTheme.heroGradient }
    }
}

// MARK: - Widget

struct SunMoonWidget: Widget {
    let kind = "AppPersonalSunMoonWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: SunMoonProvider()) { entry in
            SunMoonWidgetView(entry: entry)
        }
        .configurationDisplayName("Sol y Luna")
        .description("Orto y ocaso del sol, fase lunar y próxima luna. Elige la ciudad en «Editar widget».")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
