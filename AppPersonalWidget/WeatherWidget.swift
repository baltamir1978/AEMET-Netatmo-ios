import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct WeatherEntry: TimelineEntry {
    let date: Date
    let netatmo: NetatmoSnapshot?
    let aemet: AemetSnapshot?
}

// MARK: - Provider

struct WeatherProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), netatmo: WidgetStore.loadNetatmo(), aemet: WidgetStore.loadAemet())
    }

    func snapshot(for configuration: SelectLocationIntent, in context: Context) async -> WeatherEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectLocationIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let e = entry(for: configuration)
        // Snapshots only change when the app refreshes; recheck in ~30 min.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [e], policy: .after(next))
    }

    private func entry(for configuration: SelectLocationIntent) -> WeatherEntry {
        let loc = resolveWidgetLocation(configuration)
        let aemet = WidgetStore.loadAemet(code: loc.code) ?? WidgetStore.loadAemet()
        // The Netatmo sensor belongs to one physical place — show it only on its own town.
        let all = WidgetStore.loadNetatmo()
        let netatmo = stationMatches(all, loc) ? all : nil
        return WeatherEntry(date: Date(), netatmo: netatmo, aemet: aemet)
    }

    /// True when the configured location is the Netatmo station's town (or coords unknown).
    private func stationMatches(_ n: NetatmoSnapshot?, _ loc: SavedLocation) -> Bool {
        guard let n else { return false }
        guard let lat = n.lat, let lon = n.lon else { return true }   // legacy snapshot: don't hide
        return abs(lat - loc.lat) < 0.3 && abs(lon - loc.lon) < 0.3
    }
}

// MARK: - View

struct WeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default:           medium
            }
        }
        .containerBackground(for: .widget) { WidgetTheme.heroGradient }
    }

    // The big number: prefer the real Netatmo reading, fall back to AEMET's current hour.
    private var currentTemp: Int? {
        if let t = entry.netatmo?.temperature { return Int(t.rounded()) }
        return entry.aemet?.currentTemp
    }

    private var locationTitle: String {
        entry.aemet?.municipio ?? entry.netatmo?.stationName ?? "—"
    }

    /// Drops today's already-elapsed hours so a stale snapshot still advances
    /// (the app caches AEMET data for up to 3h between live fetches).
    private var upcomingHours: [AemetHourPoint] {
        let nowHour = Calendar.current.component(.hour, from: Date())
        return (entry.aemet?.hourly ?? []).filter { !$0.isToday || $0.hour >= nowHour }
    }

    /// Compact AEMET warning pill: icon-only on the small widget, icon + phenomenon
    /// on the medium (a slightly chunkier capsule so it shows a bit more yellow).
    @ViewBuilder private func alertChip(compact: Bool) -> some View {
        if let alert = entry.aemet?.alert {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                if !compact { Text(alert.phenomenon).lineLimit(1) }
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 4 : 18).padding(.vertical, 2)
            // Medium: let the capsule stretch across the rest of the row so it shows
            // more yellow; small stays icon-only and hugs its content.
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .background(alert.color, in: Capsule())
        }
    }

    /// Full-width AEMET warning banner for the large widget: spans the widget so the
    /// phenomenon and level read in full instead of truncating.
    @ViewBuilder private var alertBanner: some View {
        if let alert = entry.aemet?.alert {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(alert.phenomenon).fontWeight(.bold)
                Text("· aviso \(alert.levelName)").foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alert.color, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Small

    @ViewBuilder private var small: some View {
        if entry.netatmo == nil && entry.aemet == nil {
            placeholderContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(locationTitle).font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    alertChip(compact: true)
                }
                HStack(alignment: .top, spacing: 4) {
                    Text(currentTemp.map { "\($0)°" } ?? "—")
                        .font(.system(size: 44, weight: .regular)).foregroundStyle(.white)
                    if let code = entry.aemet?.skyCode {
                        Image(systemName: SkyIcon.symbol(for: code))
                            .font(.title3)
                            .foregroundStyle(.white, SkyIcon.color(for: code))
                            .padding(.top, 6)
                    }
                }
                if let a = entry.aemet {
                    Text(a.skyDescription).font(.caption2)
                        .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if entry.aemet?.tempMax != nil || entry.aemet?.tempMin != nil {
                    HStack(spacing: 8) {
                        if let mx = entry.aemet?.tempMax {
                            Label("\(mx)°", systemImage: "arrow.up").foregroundStyle(.white)
                        }
                        if let mn = entry.aemet?.tempMin {
                            Label("\(mn)°", systemImage: "arrow.down").foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .font(.caption.weight(.medium)).labelStyle(.titleAndIcon)
                }
                if let n = entry.netatmo {
                    HStack(spacing: 8) {
                        if let h = n.humidity { Label("\(Int(h))%", systemImage: "humidity.fill") }
                        if let p = n.pressure { Label("\(Int(p))", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                    }
                    .font(.caption2).foregroundStyle(.white.opacity(0.8)).labelStyle(.titleAndIcon)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Medium

    @ViewBuilder private var medium: some View {
        if entry.netatmo == nil && entry.aemet == nil {
            placeholderContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // .center keeps the right column (máx/mín, plus Netatmo when on its own
                // town) vertically centred: when Netatmo is absent the máx/mín drops to
                // the middle, leaving the top row free so the alert capsule can run longer.
                HStack(alignment: .center) {
                    currentLeft(tempSize: 38)
                    Spacer(minLength: 8)
                    trailingDetails(showUpdated: false, maxMinFont: .title3.weight(.semibold))
                }
                Spacer(minLength: 0)
                let hours = upcomingHours
                if !hours.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(hours.prefix(5).enumerated()), id: \.offset) { _, h in
                            hourColumn(h).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Large

    @ViewBuilder private var large: some View {
        if entry.netatmo == nil && entry.aemet == nil {
            placeholderContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    currentLeft(tempSize: 50, showAlert: false)
                    Spacer(minLength: 8)
                    trailingDetails(showUpdated: true)
                }
                if entry.aemet?.alert != nil {
                    alertBanner.padding(.top, 8)
                }
                let hours = upcomingHours
                if !hours.isEmpty {
                    Divider().overlay(.white.opacity(0.25)).padding(.vertical, 10)
                    HStack(spacing: 0) {
                        ForEach(Array(hours.prefix(6).enumerated()), id: \.offset) { _, h in
                            hourColumn(h).frame(maxWidth: .infinity)
                        }
                    }
                }
                if let days = entry.aemet?.daily, !days.isEmpty {
                    Divider().overlay(.white.opacity(0.25)).padding(.vertical, 10)
                    let mins = days.prefix(5).compactMap(\.tempMin)
                    let maxs = days.prefix(5).compactMap(\.tempMax)
                    let weekMin = mins.min() ?? 0
                    let weekMax = maxs.max() ?? (weekMin + 1)
                    VStack(spacing: 0) {
                        ForEach(Array(days.prefix(5).enumerated()), id: \.offset) { i, d in
                            dayRow(d, weekMin: weekMin, weekMax: weekMax)
                            if i < min(4, days.count - 1) {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Shared pieces

    /// Location + big temperature + condition (left side of medium & large).
    private func currentLeft(tempSize: CGFloat, showAlert: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(locationTitle).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white).lineLimit(1).layoutPriority(1)
                if showAlert { alertChip(compact: false) }
            }
            HStack(alignment: .top, spacing: 6) {
                Text(currentTemp.map { "\($0)°" } ?? "—")
                    .font(.system(size: tempSize, weight: .regular)).foregroundStyle(.white)
                if let code = entry.aemet?.skyCode {
                    Image(systemName: SkyIcon.symbol(for: code))
                        .font(.title2)
                        .foregroundStyle(.white, SkyIcon.color(for: code))
                        .padding(.top, tempSize * 0.18)
                }
            }
            if let a = entry.aemet {
                Text(a.skyDescription).font(.caption)
                    .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
        }
    }

    /// Max/min + Netatmo humidity & pressure (right side of medium & large).
    private func trailingDetails(showUpdated: Bool,
                                 maxMinFont: Font = .subheadline.weight(.medium)) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if entry.aemet?.tempMax != nil || entry.aemet?.tempMin != nil {
                HStack(spacing: 8) {
                    if let mx = entry.aemet?.tempMax {
                        Label("\(mx)°", systemImage: "arrow.up").foregroundStyle(.white)
                    }
                    if let mn = entry.aemet?.tempMin {
                        Label("\(mn)°", systemImage: "arrow.down").foregroundStyle(.white.opacity(0.7))
                    }
                }
                .font(maxMinFont)
                .labelStyle(.titleAndIcon)
            }
            if let n = entry.netatmo {
                if let h = n.humidity {
                    Label("\(Int(h))%", systemImage: "humidity.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                if let p = n.pressure {
                    Label("\(Int(p)) hPa", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                if showUpdated {
                    Text("Act. \(timeString(n.date))")
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func hourColumn(_ h: AemetHourPoint) -> some View {
        VStack(spacing: 4) {
            Text(h.isToday ? String(format: "%02d", h.hour) : weekday(forHour: h))
                .font(.caption2).foregroundStyle(.white.opacity(0.8))
            Image(systemName: SkyIcon.symbol(for: h.skyCode))
                .font(.body)
                .foregroundStyle(.white, SkyIcon.color(for: h.skyCode))
                .frame(height: 20)
            Text("\(h.temp)°").font(.footnote.weight(.semibold)).foregroundStyle(.white)
            if let p = h.prob, p > 0 {
                Text("\(p)%").font(.system(size: 9)).foregroundStyle(WidgetTheme.greenBright)
            } else {
                Text(" ").font(.system(size: 9))
            }
        }
    }

    private func dayRow(_ d: AemetDayPoint, weekMin: Int, weekMax: Int) -> some View {
        HStack(spacing: 8) {
            Text(weekday(d.date)).font(.subheadline.weight(.medium))
                .foregroundStyle(.white).frame(width: 42, alignment: .leading)
            Image(systemName: SkyIcon.symbol(for: d.skyCode))
                .font(.body)
                .foregroundStyle(.white, SkyIcon.color(for: d.skyCode))
                .frame(width: 24)
            if let p = d.prob, p > 0 {
                Label("\(p)%", systemImage: "drop.fill")
                    .font(.caption2).foregroundStyle(WidgetTheme.greenBright)
                    .labelStyle(.titleAndIcon).frame(width: 44, alignment: .leading)
            } else {
                Spacer().frame(width: 44)
            }
            Text(d.tempMin.map { "\($0)°" } ?? "—")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                .frame(width: 30, alignment: .trailing)
            rangeBar(min: d.tempMin, max: d.tempMax, weekMin: weekMin, weekMax: weekMax)
            Text(d.tempMax.map { "\($0)°" } ?? "—")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 30, alignment: .leading)
        }
    }

    /// Apple-style horizontal min–max bar, sized to the week's overall range.
    private func rangeBar(min dMin: Int?, max dMax: Int?, weekMin: Int, weekMax: Int) -> some View {
        GeometryReader { geo in
            let span = CGFloat(max(1, weekMax - weekMin))
            let w = geo.size.width
            let lo = CGFloat((dMin ?? weekMin) - weekMin) / span * w
            let hi = CGFloat((dMax ?? weekMax) - weekMin) / span * w
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2)).frame(height: 4)
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, WidgetTheme.sun],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, hi - lo), height: 4)
                    .offset(x: lo)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 18)
        .frame(maxWidth: .infinity)
    }

    private var placeholderContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2).foregroundStyle(.white.opacity(0.85))
            Text("Abre la app para actualizar")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Formatting

    private func weekday(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Hoy" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        return f.string(from: date).capitalized
    }

    /// For tomorrow's hours in the strip, show the weekday instead of the bare hour.
    private func weekday(forHour h: AemetHourPoint) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        return f.string(from: Date().addingTimeInterval(86400)).capitalized
    }
}

// MARK: - Widget

struct WeatherWidget: Widget {
    let kind = "AppPersonalWeatherWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Tiempo")
        .description("Pronóstico AEMET (actual, por horas y próximos días) + tu estación Netatmo. Elige la ciudad en «Editar widget».")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
