import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Station selection (Editar widget → Estación)

/// A tide station shown in the widget's configuration. Backed by `ihmStations`.
struct TideStationEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Estación de mareas" }
    static var defaultQuery = TideStationQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct TideStationQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TideStationEntity] {
        identifiers.compactMap { id in
            ihmStations.first { $0.id == id }.map { TideStationEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [TideStationEntity] {
        ihmStations.map { TideStationEntity(id: $0.id, name: $0.name) }
    }

    /// Default to Llanes (matches the app's default tide station).
    func defaultResult() async -> TideStationEntity? {
        let s = ihmStations.first { $0.id == "4" } ?? ihmStations.first
        return s.map { TideStationEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectTideStationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Estación de mareas"
    static var description = IntentDescription("Elige el puerto cuyas mareas muestra el widget.")

    @Parameter(title: "Estación")
    var station: TideStationEntity?

    init() {}
}

private func resolveTideStation(_ intent: SelectTideStationIntent) -> TideStation {
    if let s = intent.station, let match = ihmStations.first(where: { $0.id == s.id }) {
        return match
    }
    return ihmStations.first { $0.id == "4" } ?? ihmStations[0]
}

// MARK: - Entry

/// One sampled high/low used to draw the curve. Minutes are measured from
/// `dayStart`, so tomorrow's tides land past 1440 and interpolate cleanly.
struct TideExtreme: Codable, Hashable {
    let minutes: Double
    let height: Double
    let isHigh: Bool
}

struct TidesEntry: TimelineEntry {
    let date: Date
    let stationName: String
    let extrema: [TideExtreme]
    let dayStart: Date
    let sunriseMin: Double?   // minutes from dayStart, station's sunrise
    let sunsetMin: Double?    // minutes from dayStart, station's sunset
}

// MARK: - Provider

struct TidesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TidesEntry {
        let day = Self.dayStart(Date())
        return TidesEntry(date: Date(), stationName: "Mareas",
                          extrema: Self.sampleExtrema(from: Date()), dayStart: day,
                          sunriseMin: 8 * 60, sunsetMin: 21 * 60)
    }

    func snapshot(for configuration: SelectTideStationIntent, in context: Context) async -> TidesEntry {
        await entry(for: configuration, at: Date())
    }

    func timeline(for configuration: SelectTideStationIntent, in context: Context) async -> Timeline<TidesEntry> {
        let now = Date()
        let station = resolveTideStation(configuration)
        let dayStart = Self.dayStart(now)
        let extrema = await Self.fetchExtrema(station: station, dayStart: dayStart)
        let sun = Self.sunTimes(station: station, dayStart: dayStart)

        // Re-use one fetch for several entries so the "now" marker advances on its
        // own (each entry recomputes its position from `date`) without re-querying.
        let entries = (0..<18).compactMap { step -> TidesEntry? in
            Calendar.current.date(byAdding: .minute, value: step * 20, to: now).map {
                TidesEntry(date: $0, stationName: station.name, extrema: extrema, dayStart: dayStart,
                           sunriseMin: sun.rise, sunsetMin: sun.set)
            }
        }
        let refresh = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func entry(for configuration: SelectTideStationIntent, at date: Date) async -> TidesEntry {
        let station = resolveTideStation(configuration)
        let dayStart = Self.dayStart(date)
        let extrema = await Self.fetchExtrema(station: station, dayStart: dayStart)
        let sun = Self.sunTimes(station: station, dayStart: dayStart)
        return TidesEntry(date: date, stationName: station.name, extrema: extrema, dayStart: dayStart,
                          sunriseMin: sun.rise, sunsetMin: sun.set)
    }

    /// The station's sunrise/sunset (minutes from dayStart) so the widget can tell
    /// day from night and label both times.
    private static func sunTimes(station: TideStation, dayStart: Date) -> (rise: Double?, set: Double?) {
        let loc = SunMoonLocation(key: station.id, name: station.name,
                                  lat: station.lat, lon: station.lon, elevation: 0, tz: "Europe/Madrid")
        let r = SunMoonService.shared.calculate(location: loc, date: dayStart)
        return (r.sun.sunrise.flatMap(minutes(from:)), r.sun.sunset.flatMap(minutes(from:)))
    }

    // MARK: Data

    private static func dayStart(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return cal.startOfDay(for: date)
    }

    private static func fetchExtrema(station: TideStation, dayStart: Date) async -> [TideExtreme] {
        guard let pair = try? await TidesService.shared.tides(
            for: dayStart, stationId: station.id, stationName: station.name) else { return [] }
        return extrema(from: pair)
    }

    /// Flatten a two-day tide pair into a sorted extrema list in minutes-from-dayStart.
    private static func extrema(from pair: TidesDayPair) -> [TideExtreme] {
        var out: [TideExtreme] = []
        for (dayIndex, day) in pair.days.enumerated() {
            for tide in day.tides {
                guard let m = minutes(from: tide.time) else { continue }
                out.append(TideExtreme(minutes: m + Double(dayIndex) * 1440,
                                       height: tide.height,
                                       isHigh: tide.type == "pleamar"))
            }
        }
        return out.sorted { $0.minutes < $1.minutes }
    }

    private static func minutes(from hhmm: String) -> Double? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Double(parts[0]), let m = Double(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// Synthetic extrema for placeholders/previews (~12.4h tidal period).
    private static func sampleExtrema(from date: Date) -> [TideExtreme] {
        let base = 100.0
        return (0..<5).map { i in
            TideExtreme(minutes: base + Double(i) * 372,
                        height: i.isMultiple(of: 2) ? 1.1 : 3.9,
                        isHigh: !i.isMultiple(of: 2))
        }
    }
}

// MARK: - Curve geometry

/// Smooth tidal curve through the extrema using cosine (smooth-step) segments,
/// which have zero slope at each high/low — the natural tidal shape.
struct TideCurve {
    let extrema: [TideExtreme]   // sorted, real points
    let domain: ClosedRange<Double>

    /// Extrema padded with mirrored virtual ends so interpolation covers `domain`.
    private var padded: [TideExtreme] {
        guard extrema.count >= 2 else { return extrema }
        var e = extrema
        let a0 = e[0], a1 = e[1]
        e.insert(TideExtreme(minutes: a0.minutes - (a1.minutes - a0.minutes),
                             height: a1.height, isHigh: a1.isHigh), at: 0)
        let bN = e[e.count - 1], bP = e[e.count - 2]
        e.append(TideExtreme(minutes: bN.minutes + (bN.minutes - bP.minutes),
                             height: bP.height, isHigh: bP.isHigh))
        return e
    }

    func height(at m: Double) -> Double {
        let e = padded
        guard let first = e.first, let last = e.last else { return 0 }
        if m <= first.minutes { return first.height }
        if m >= last.minutes { return last.height }
        for i in 0..<(e.count - 1) {
            let a = e[i], b = e[i + 1]
            if m >= a.minutes && m <= b.minutes {
                let frac = (m - a.minutes) / (b.minutes - a.minutes)
                let t = (1 - cos(.pi * frac)) / 2
                return a.height + (b.height - a.height) * t
            }
        }
        return last.height
    }

    /// Height range over the visible window, padded so the curve never touches edges.
    var visibleRange: (min: Double, max: Double) {
        let step = (domain.upperBound - domain.lowerBound) / 64
        let ys = stride(from: domain.lowerBound, through: domain.upperBound, by: step).map(height(at:))
        let lo = ys.min() ?? 0, hi = ys.max() ?? 1
        let pad = max(0.1, (hi - lo) * 0.18)
        return (lo - pad, hi + pad)
    }

    /// The next real high/low after `m`, used for "rising/falling" + next-tide label.
    func nextExtreme(after m: Double) -> TideExtreme? {
        extrema.first { $0.minutes > m }
    }
}

// MARK: - View

struct TidesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TidesEntry

    private var nowMinutes: Double { entry.date.timeIntervalSince(entry.dayStart) / 60 }

    // Kept only to read the current height (smooth cosine curve through the extrema);
    // the widget no longer draws the 12h curve, it draws a beach whose water level is
    // that height. A wide window so the interpolation always has extrema on both sides.
    private var window: ClosedRange<Double> { (nowMinutes - 360)...(nowMinutes + 720) }
    private var curve: TideCurve { TideCurve(extrema: entry.extrema, domain: window) }

    /// Daytime when "now" sits between the station's sunrise and sunset.
    private var isDay: Bool {
        guard let rise = entry.sunriseMin, let set = entry.sunsetMin else { return true }
        let m = nowMinutes.truncatingRemainder(dividingBy: 1440)
        return m >= rise && m <= set
    }

    private var currentHeight: Double { curve.height(at: nowMinutes) }
    private var next: TideExtreme? { curve.nextExtreme(after: nowMinutes) }
    private var rising: Bool { next?.isHigh ?? false }

    var body: some View {
        Group {
            if entry.extrema.count >= 2 {
                switch family {
                case .systemSmall: small
                default:           medium
                }
            } else {
                unavailable
            }
        }
        // Full-bleed frame + widgetURL before containerBackground so every family (incl.
        // large) reliably opens the Mareas card in the app's Sol·Luna tab on tap.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetDeepLink.url(WidgetDeepLink.tides))
        .containerBackground(for: .widget) { beach }
    }

    // MARK: - Beach background (water level ∝ current tide within the day's range)

    /// Sand (top) → water (bottom), the waterline at a height set by the current tide:
    /// near the day's high the widget is mostly water, near the low it's mostly sand.
    /// The surface carries a soft, fixed ripple (widgets don't animate).
    @ViewBuilder private var beach: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let heights = entry.extrema.map(\.height)
            let dayLow = heights.min() ?? 0
            let dayHigh = heights.max() ?? (dayLow + 1)
            let f = max(0, min(1, (currentHeight - dayLow) / max(0.01, dayHigh - dayLow)))
            let levelY = h * (1 - (0.10 + 0.80 * f))   // 10% water at the low → 90% at the high
            let pts = surfacePoints(w: w, h: h, levelY: levelY)

            ZStack {
                LinearGradient(colors: sandColors, startPoint: .top, endPoint: .bottom)
                // Darker wet-sand band right above the waterline reads as the shoreline.
                Rectangle().fill(wetSand).opacity(0.5)
                    .frame(height: 12).position(x: w / 2, y: levelY - 3)
                waterPath(pts, w: w, h: h)
                    .fill(LinearGradient(colors: waterColors, startPoint: .top, endPoint: .bottom))
                ripplePath(pts, dy: 5)
                    .stroke(foam.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                ripplePath(pts, dy: 0)
                    .stroke(foam.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                // Sun by day / moon by night, in the "sky" over the beach.
                ZStack {
                    Circle().fill(isDay ? WidgetTheme.sun : Color(red: 0.93, green: 0.95, blue: 1.0))
                        .frame(width: 28, height: 28)
                    Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isDay ? .orange : .indigo)
                }
                .position(x: w - 24, y: 24)
            }
        }
        .accessibilityHidden(true)   // decorative; the labels below carry the reading
    }

    private func surfacePoints(w: CGFloat, h: CGFloat, levelY: CGFloat) -> [CGPoint] {
        let steps = max(40, Int(w / 3))
        let amp = max(0.5, h * 0.005)        // gentle ripple, not chop
        let lambda = 24.0, phase = 0.6       // long wavelength; fixed phase (static widget)
        return (0...steps).map { i in
            let x = w * CGFloat(i) / CGFloat(steps)
            let d = Double(x)
            let y = levelY
                + CGFloat(sin(d / lambda + phase)) * amp
                + CGFloat(sin(d / (lambda * 0.6) - phase * 1.2)) * amp * 0.4
            return CGPoint(x: x, y: y)
        }
    }

    private func waterPath(_ pts: [CGPoint], w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: first)
        pts.dropFirst().forEach { p.addLine(to: $0) }
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }

    private func ripplePath(_ pts: [CGPoint], dy: CGFloat) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: CGPoint(x: first.x, y: first.y + dy))
        pts.dropFirst().forEach { p.addLine(to: CGPoint(x: $0.x, y: $0.y + dy)) }
        return p
    }

    // Beach tones: warm yellow sand and a sunny/deep sea, dimmed at night.
    private var sandColors: [Color] {
        isDay ? [Color(red: 0.925, green: 0.835, blue: 0.537), Color(red: 0.831, green: 0.706, blue: 0.373)]
              : [Color(red: 0.514, green: 0.416, blue: 0.251), Color(red: 0.357, green: 0.278, blue: 0.157)]
    }
    private var waterColors: [Color] {
        isDay ? [Color(red: 0.227, green: 0.643, blue: 0.867), Color(red: 0.047, green: 0.353, blue: 0.573)]
              : [Color(red: 0.122, green: 0.435, blue: 0.627), Color(red: 0.024, green: 0.165, blue: 0.271)]
    }
    private var foam: Color {
        isDay ? Color(red: 0.918, green: 0.969, blue: 1.0) : Color(red: 0.812, green: 0.918, blue: 0.984)
    }
    private var wetSand: Color { sandColors[1] }

    // Text sits on either sand or water, so every label gets a soft shadow.
    private let textShadow = Color.black.opacity(0.4)

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(entry.stationName, systemImage: "water.waves")
                .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                Text(String(format: "%.1f m", currentHeight))
            }
            .font(.headline).foregroundStyle(.white)
            Spacer(minLength: 0)
            sunRow
            nextLabel.font(.caption2).foregroundStyle(.white).lineLimit(1)
        }
        .shadow(color: textShadow, radius: 2, x: 0, y: 1)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.stationName, systemImage: "water.waves")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                Text(String(format: "%.2f m", currentHeight))
            }
            .font(.title3.weight(.bold)).foregroundStyle(.white)
            sunRow
            Spacer(minLength: 0)
            HStack {
                Text(rising ? "Subiendo" : "Bajando")
                    .font(.caption2.weight(.medium)).foregroundStyle(.white)
                Spacer()
                nextLabel.font(.caption2).foregroundStyle(.white)
            }
        }
        .shadow(color: textShadow, radius: 2, x: 0, y: 1)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Station sunrise/sunset, shown under the name.
    @ViewBuilder private var sunRow: some View {
        if let rise = entry.sunriseMin, let set = entry.sunsetMin {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "sunrise.fill").foregroundStyle(WidgetTheme.sun)
                    Text(timeLabel(rise))
                }
                HStack(spacing: 3) {
                    Image(systemName: "sunset.fill").foregroundStyle(.orange)
                    Text(timeLabel(set))
                }
            }
            .font(.caption2).foregroundStyle(.white)
        }
    }

    @ViewBuilder private var nextLabel: some View {
        if let n = next {
            HStack(spacing: 4) {
                Text(n.isHigh ? "🌊 Pleamar" : "🏖️ Bajamar")
                Text(timeLabel(n.minutes))
                Text(String(format: "· %.1f m", n.height))
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: "water.waves.slash").font(.title2).foregroundStyle(.white.opacity(0.85))
            Text("Sin datos de mareas").font(.caption2).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeLabel(_ minutes: Double) -> String {
        let date = entry.dayStart.addingTimeInterval(minutes * 60)
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Widget

struct TidesWidget: Widget {
    let kind = "AppPersonalTidesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectTideStationIntent.self, provider: TidesProvider()) { entry in
            TidesWidgetView(entry: entry)
        }
        .configurationDisplayName("Mareas")
        .description("Curva de marea del día con tu posición actual. Elige el puerto en «Editar widget».")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
