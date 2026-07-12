import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

/// Purely AEMET (station reading + forecast): every number here comes from the same place
/// the app's Tiempo tab reads. The Netatmo sensor sits in one specific garden and reads a
/// couple of degrees off the station, so mixing it in here was what made the widget and the
/// app disagree — it has its own widget (`NetatmoWidget`) for that reading.
struct WeatherEntry: TimelineEntry {
    let date: Date
    let aemet: AemetSnapshot?
}

// MARK: - Provider

struct WeatherProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), aemet: WidgetStore.loadAemet())
    }

    func snapshot(for configuration: SelectLocationIntent, in context: Context) async -> WeatherEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectLocationIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let loc = resolveWidgetLocation(configuration)
        // Pull fresh AEMET data ourselves so the widget updates even if the app
        // hasn't been opened; falls back to the stored snapshot on any failure.
        let e = await freshEntry(for: loc)
        // Next refresh follows the user's chosen cadence (Ajustes · 1/3/6/12 h).
        let next = Date().addingTimeInterval(WidgetStore.loadRefreshInterval().seconds)
        return Timeline(entries: [e], policy: .after(next))
    }

    /// Snapshot/placeholder path: read whatever's already in the store (no network).
    private func entry(for configuration: SelectLocationIntent) -> WeatherEntry {
        let loc = resolveWidgetLocation(configuration)
        let aemet = WidgetStore.loadAemet(code: loc.code) ?? WidgetStore.loadAemet()
        return WeatherEntry(date: Date(), aemet: aemet)
    }

    /// Timeline path: try a live fetch for the configured city, write it back to the
    /// shared store (so the app and sibling widgets benefit), and fall back to the stored
    /// snapshot when offline / rate-limited. The AEMET warning badge is carried over from
    /// the stored snapshot (the widget can't fetch it).
    private func freshEntry(for loc: SavedLocation) async -> WeatherEntry {
        let stored = WidgetStore.loadAemet(code: loc.code) ?? WidgetStore.loadAemet()
        let fresh = await freshSnapshot(for: loc, alert: stored?.alert)
        if let fresh {
            WidgetStore.save(aemet: fresh, forCode: loc.code)
        }
        return WeatherEntry(date: Date(), aemet: fresh ?? stored)
    }

    /// A newly fetched snapshot for `loc`, from AEMET when a key is configured and from
    /// Open-Meteo otherwise — the same provider split the app's AEMET tab makes. Without
    /// the Open-Meteo branch a key-less install left the widget frozen on whatever the app
    /// last wrote, since nothing else refreshes it in the background. Nil when the fetch fails.
    private func freshSnapshot(for loc: SavedLocation, alert: AemetAlertBadge?) async -> AemetSnapshot? {
        guard (WidgetStore.loadAemetApiKey() ?? "").isEmpty == false else {
            guard let f = await OpenMeteoService.shared.fetchForecast(lat: loc.lat, lon: loc.lon) else { return nil }
            return AemetSnapshotBuilder.makeAemetSnapshot(
                municipio: loc.name, daily: f.daily, hourly: f.hourly, observation: f.obs, alert: alert)
        }
        // 30-min disk cache: a timeline rebuild within the window reuses it,
        // so we don't hammer AEMET's rate-limited API on every WidgetKit poll.
        async let d = try? await AEMETService.shared.forecastDaily(municipio: loc.code, maxAge: 30 * 60)
        async let h = try? await AEMETService.shared.forecastHourly(municipio: loc.code, maxAge: 30 * 60)
        let (dr, hr) = await (d, h)
        guard dr != nil || hr != nil else { return nil }
        var obs: [AemetObservationRecord]? = nil
        if let id = loc.idema {
            obs = try? await AEMETService.shared.observation(idema: id, maxAge: 30 * 60)
        }
        return AemetSnapshotBuilder.makeAemetSnapshot(
            municipio: loc.name, daily: dr, hourly: hr, observation: obs, alert: alert)
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

    // The big number, and the same chain the app's Tiempo hero uses (station reading →
    // current-hour forecast → daily max), so both screens always agree. The Netatmo sensor
    // is a different thermometer in a different spot: preferring it here made the widget
    // disagree with the app by several degrees. It has its own widget for that reading.
    // The hourly fallback matters because AEMET sometimes prunes the current (partial)
    // hour from its forecast; the hourly strip is range-based, so it always has a point.
    private var currentTemp: Int? {
        entry.aemet?.currentTemp ?? entry.aemet?.hourly?.first?.temp ?? entry.aemet?.tempMax
    }

    private var locationTitle: String {
        entry.aemet?.municipio ?? "—"
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
        if entry.aemet == nil {
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
                if entry.aemet?.humidity != nil || entry.aemet?.windKmh != nil {
                    HStack(spacing: 8) {
                        if let h = entry.aemet?.humidity {
                            Label("\(h)%", systemImage: "humidity.fill")
                                .accessibilityLabel(Text("Humedad \(h) por ciento"))
                        }
                        if let w = entry.aemet?.windKmh {
                            // Unit dropped on the small family — the wind icon carries it,
                            // and "12 km/h" next to the humidity chip wraps at this width.
                            Label("\(w)", systemImage: "wind")
                                .accessibilityLabel(Text("Viento \(w) kilómetros por hora"))
                        }
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
        if entry.aemet == nil {
            placeholderContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Location + alert live in their own full-width top row so the capsule can
                // run across the whole widget (the right column below holds máx/mín, which
                // is centred lower down and leaves this top band free). The extra 4 pt on
                // top drops the town name away from the widget's edge, and the tighter stack
                // spacing more than pays for it — the medium has no slack at the bottom, so
                // any net height added here pushes the hourly row's rain % off the widget.
                HStack(spacing: 5) {
                    Text(locationTitle).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white).lineLimit(1).layoutPriority(1)
                    alertChip(compact: false)
                }
                .padding(.top, 2)
                // .top aligns máx/mín with the top of the big temperature so they don't
                // drift to the vertical middle of the (now location-less) left column.
                HStack(alignment: .top) {
                    currentLeft(tempSize: 38, showAlert: false, showLocation: false)
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
        if entry.aemet == nil {
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
    /// `showLocation` lets the medium hoist the location+alert into its own full-width
    /// top row (so the capsule can use the free space above máx/mín).
    private func currentLeft(tempSize: CGFloat, showAlert: Bool = true,
                             showLocation: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if showLocation {
                HStack(spacing: 5) {
                    Text(locationTitle).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white).lineLimit(1).layoutPriority(1)
                    if showAlert { alertChip(compact: false) }
                }
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

    /// Max/min + the station's humidity & wind (right side of medium & large) — all AEMET,
    /// so every figure on the widget matches the app's Tiempo hero.
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
            if let a = entry.aemet {
                if let h = a.humidity {
                    Label("\(h)%", systemImage: "humidity.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                        .accessibilityLabel(Text("Humedad \(h) por ciento"))
                }
                if let w = a.windKmh {
                    Label("\(w) km/h", systemImage: "wind")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                        .accessibilityLabel(Text("Viento \(w) kilómetros por hora"))
                }
                if showUpdated {
                    Text("Act. \(timeString(a.date))")
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
                    // Draw at natural width so "100%" (one digit wider) never gets an ellipsis;
                    // it's tiny next to the column width, so it can't overlap neighbours.
                    .lineLimit(1).fixedSize()
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
                // Draw the drop + "%" at natural width so "100%" (a digit wider) never
                // gets an ellipsis; the fixed 48pt slot keeps the columns aligned.
                Label("\(p)%", systemImage: "drop.fill")
                    .font(.caption2).foregroundStyle(WidgetTheme.greenBright)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1).fixedSize()
                    .frame(width: 48, alignment: .leading)
            } else {
                Spacer().frame(width: 48)
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
        .description("Pronóstico AEMET: temperatura actual de la estación, por horas y próximos días. Elige la ciudad en «Editar widget».")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
