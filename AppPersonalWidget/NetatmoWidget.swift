import WidgetKit
import SwiftUI

// Dedicated widget for the Netatmo station: exterior + interior, in three sizes.
//
// Unlike the weather widget this one can't self-fetch — Netatmo is OAuth-only and the
// tokens live in the app — so it renders the last `NetatmoSnapshot` the app stored (Actual
// tab or background refresh) and says how old it is. Hence the visible "Act. HH:mm".
//
// Design note: the first cut was a grid of bare numbers (41% · 1020 · 0 L · 768 · 60 dB) and
// read like a spreadsheet. A widget is glanced at, not studied — so each sensor is now a
// *ring* whose fill shows where the reading sits in its comfort range, and the day's
// temperature is a range bar with a dot for "now". The number is still there, but you can
// read the widget without reading a single digit.

struct NetatmoEntry: TimelineEntry {
    let date: Date
    let snap: NetatmoSnapshot?
    var background: NetatmoBackground = .theme
}

struct NetatmoProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NetatmoEntry {
        NetatmoEntry(date: Date(), snap: WidgetStore.loadNetatmo())
    }

    func snapshot(for configuration: NetatmoStyleIntent, in context: Context) async -> NetatmoEntry {
        NetatmoEntry(date: Date(), snap: WidgetStore.loadNetatmo(), background: configuration.background)
    }

    func timeline(for configuration: NetatmoStyleIntent, in context: Context) async -> Timeline<NetatmoEntry> {
        let entry = NetatmoEntry(date: Date(), snap: WidgetStore.loadNetatmo(),
                                 background: configuration.background)
        // Re-read the store on the user's cadence; the app is what actually refreshes it.
        let next = Date().addingTimeInterval(WidgetStore.loadRefreshInterval().seconds)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

// MARK: - Gauges

/// A sensor as a ring: the arc shows where the reading sits between `min` and `max`, so the
/// shape carries the meaning and the number is only confirmation.
private struct SensorRing: View {
    let value: Double
    let min: Double
    let max: Double
    let icon: String
    let tint: Color
    let text: String
    let caption: LocalizedStringResource
    var size: CGFloat = 44

    private var fraction: Double {
        guard max > min else { return 0 }
        return Swift.min(1, Swift.max(0, (value - min) / (max - min)))
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(.white.opacity(0.22), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: icon)
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: size, height: size)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.white)
            Text(caption).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        // One spoken sentence per sensor — VoiceOver would otherwise read the ring, the
        // number and the caption as three unrelated fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(String(localized: caption)): \(text)"))
    }
}

/// Today's temperature range with a dot for the current reading: min ——•—— max.
private struct RangeBar: View {
    let min: Double
    let max: Double
    let current: Double?

    private var fraction: Double {
        guard let current, max > min else { return 0.5 }
        return Swift.min(1, Swift.max(0, (current - min) / (max - min)))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Int(min.rounded()))°").font(.caption2).foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).fixedSize()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, WidgetTheme.sun],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 4)
                    Circle().fill(.white)
                        .frame(width: 8, height: 8)
                        .offset(x: (geo.size.width - 8) * fraction)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 10)
            Text("\(Int(max.rounded()))°").font(.caption2.weight(.semibold)).foregroundStyle(.white)
                .lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Máxima \(Int(max.rounded()))°, mínima \(Int(min.rounded()))°"))
    }
}

// MARK: - View

struct NetatmoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NetatmoEntry

    var body: some View {
        Group {
            if let s = entry.snap {
                switch family {
                case .systemSmall: small(s)
                case .systemLarge: large(s)
                default:           medium(s)
                }
            } else {
                placeholder
            }
        }
        .containerBackground(for: .widget) { background }
    }

    /// Green like the rest of the app, or the outdoor temperature's own colour.
    @ViewBuilder private var background: some View {
        switch entry.background {
        case .temperature: TempPalette.gradient(for: entry.snap?.temperature)
        case .theme:       WidgetTheme.heroGradient
        }
    }

    // MARK: Small — one number, one shape: outdoor temperature and where it sits today.

    private func small(_ s: NetatmoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(s)
            Text(temp(s.temperature))
                .font(.system(size: 46, weight: .light)).foregroundStyle(.white)
                .accessibilityLabel(spokenTemp("Exterior", s.temperature))
            if let mn = s.tempMinOut, let mx = s.tempMaxOut {
                RangeBar(min: mn, max: mx, current: s.temperature)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if let h = s.humidity { chip("humidity.fill", "\(Int(h))%", spoken: "Humedad") }
                if let ti = s.tempIn { chip("house.fill", temp(ti), spoken: "Interior") }
            }
            updated(s)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium — the two temperatures, each with its one telling gauge.

    private func medium(_ s: NetatmoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(s)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Exterior")
                    Text(temp(s.temperature))
                        .font(.system(size: 40, weight: .light)).foregroundStyle(.white)
                        .accessibilityLabel(spokenTemp("Exterior", s.temperature))
                    if let mn = s.tempMinOut, let mx = s.tempMaxOut {
                        RangeBar(min: mn, max: mx, current: s.temperature)
                    }
                }
                if let h = s.humidity { humidityRing(h) }
                Divider().overlay(.white.opacity(0.25))
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Interior")
                    Text(temp(s.tempIn))
                        .font(.system(size: 40, weight: .light)).foregroundStyle(.white)
                        .accessibilityLabel(spokenTemp("Interior", s.tempIn))
                    if let h = s.humidityIn {
                        chip("humidity.fill", "\(Int(h))%", spoken: "Humedad")
                    }
                }
                if let c = s.co2 { co2Ring(c) }
            }
            Spacer(minLength: 0)
            updated(s)      // its own footer row — it was landing mid-column before
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Large — two blocks of rings, no number grid.

    private func large(_ s: NetatmoSnapshot) -> some View {
        // Spacers *between* the blocks, not one big one at the end: the first cut piled all
        // the slack at the bottom and left a dead half-widget under the rings.
        VStack(alignment: .leading, spacing: 6) {
            header(s)
            Spacer(minLength: 0)

            sectionTitle("Exterior")
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(temp(s.temperature))
                        .font(.system(size: 52, weight: .light)).foregroundStyle(.white)
                        // The rings compete for the same row: without this the temperature
                        // gets squeezed to "2…" instead of the rings giving way.
                        .lineLimit(1).minimumScaleFactor(0.7).fixedSize()
                        .accessibilityLabel(spokenTemp("Exterior", s.temperature))
                    if let mn = s.tempMinOut, let mx = s.tempMaxOut {
                        RangeBar(min: mn, max: mx, current: s.temperature)
                    }
                }
                Spacer(minLength: 0)
                if let h = s.humidity { humidityRing(h, size: 48) }
                if let p = s.pressure { pressureRing(p, size: 48) }
                if let r = s.rainToday ?? s.rain { rainRing(r, size: 48) }
            }

            Spacer(minLength: 0)
            Divider().overlay(.white.opacity(0.25))
            Spacer(minLength: 0)

            sectionTitle("Interior")
            HStack(alignment: .center, spacing: 14) {
                Text(temp(s.tempIn))
                    .font(.system(size: 52, weight: .light)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7).fixedSize()
                    .accessibilityLabel(spokenTemp("Interior", s.tempIn))
                Spacer(minLength: 0)
                if let h = s.humidityIn { humidityRing(h, size: 48) }
                if let c = s.co2 { co2Ring(c, size: 48) }
                if let n = s.noise { noiseRing(n, size: 48) }
            }

            Spacer(minLength: 0)
            updated(s)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Rings (comfort ranges, so a full ring always means "a lot of this")

    private func humidityRing(_ h: Double, size: CGFloat = 44) -> some View {
        SensorRing(value: h, min: 0, max: 100, icon: "humidity.fill", tint: .cyan,
                   text: "\(Int(h))%", caption: "Humedad", size: size)
    }

    /// 980–1040 hPa covers everything short of a hurricane, so the arc actually moves.
    private func pressureRing(_ p: Double, size: CGFloat = 44) -> some View {
        SensorRing(value: p, min: 980, max: 1040, icon: "gauge.medium", tint: WidgetTheme.greenBright,
                   text: "\(Int(p))", caption: "Presión", size: size)
    }

    /// Netatmo's own comfort bands: ≤1000 good (white), ≤1600 fair (amber), above that poor (red).
    private func co2Ring(_ c: Double, size: CGFloat = 44) -> some View {
        SensorRing(value: c, min: 400, max: 2000, icon: "aqi.medium", tint: co2Color(c),
                   text: "\(Int(c))", caption: "CO₂ ppm", size: size)
    }

    private func noiseRing(_ n: Double, size: CGFloat = 44) -> some View {
        SensorRing(value: n, min: 30, max: 90, icon: "speaker.wave.2.fill", tint: .white.opacity(0.85),
                   text: "\(Int(n))", caption: "Ruido dB", size: size)
    }

    /// 10 mm of rain in a day is already a wet day round here — that's a full ring.
    private func rainRing(_ r: Double, size: CGFloat = 44) -> some View {
        SensorRing(value: r, min: 0, max: 10, icon: "cloud.rain.fill", tint: .cyan,
                   text: rain(r), caption: "Lluvia", size: size)
    }

    private func co2Color(_ ppm: Double) -> Color {
        if ppm > 1600 { return Color(red: 0.95, green: 0.45, blue: 0.40) }
        if ppm > 1000 { return WidgetTheme.sun }
        return WidgetTheme.greenBright
    }

    // MARK: Pieces

    private func header(_ s: NetatmoSnapshot) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sensor.fill").font(.caption2)
            Text(s.stationName).lineLimit(1).minimumScaleFactor(0.85)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.9))
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.65))
            .textCase(.uppercase)
    }

    /// Small icon + value, for the compact size where a ring wouldn't be legible.
    private func chip(_ icon: String, _ value: String, spoken: LocalizedStringResource) -> some View {
        Label(value, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.9)).labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(String(localized: spoken)): \(value)"))
    }

    private func updated(_ s: NetatmoSnapshot) -> some View {
        Text("Act. \(timeString(s.date))")
            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.title2).foregroundStyle(.white.opacity(0.85))
            Text("Abre la app para actualizar")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Formatting

    /// "18°" — one number, no decimals; "—" when the sensor didn't report.
    private func temp(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))°"
    }

    /// Rain in L/m² (= mm), one decimal — 0,2 is a real reading, "0" would hide it.
    private func rain(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .autoupdatingCurrent
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private func spokenTemp(_ title: LocalizedStringResource, _ v: Double?) -> Text {
        guard let v else { return Text("\(String(localized: title)): —") }
        return Text("\(String(localized: title)): \(Int(v.rounded())) grados")
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Widget

struct NetatmoWidget: Widget {
    let kind = "AppPersonalNetatmoWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NetatmoStyleIntent.self,
                               provider: NetatmoProvider()) { entry in
            NetatmoWidgetView(entry: entry)
        }
        .configurationDisplayName("Netatmo")
        .description("Tu estación Netatmo: temperatura y humedad exterior e interior, presión, CO₂, ruido y lluvia. El fondo puede cambiar con la temperatura («Editar widget»).")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
