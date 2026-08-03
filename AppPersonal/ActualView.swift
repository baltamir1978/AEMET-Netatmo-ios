import SwiftUI

struct ActualView: View {
    @State private var station: NetatmoDevice?
    @State private var exteriorModule: NetatmoModule?
    @State private var rainModule: NetatmoModule?
    @State private var isLoading = false
    @State private var error: String?

    /// Interior measurements (pressure lives with the exterior group instead).
    private var interiorValues: [String: Double?] {
        guard let data = station?.dashboardData else { return [:] }
        return Dictionary(uniqueKeysWithValues: data
            .filter { $0.key != "Pressure" }
            .map { ($0.key, $0.value.doubleValue) })
    }

    private var exteriorValues: [String: Double?] {
        var vals: [String: Double?] = [:]
        if let data = exteriorModule?.dashboardData {
            for (k, v) in data { vals[k] = v.doubleValue }
        }
        if let data = rainModule?.dashboardData {
            for (k, v) in data { vals[k] = v.doubleValue }
            // The card shows the last hour: fall back to the 5-minute bucket if the
            // gauge ever omits the hourly sum, so the tile never vanishes.
            if vals["sum_rain_1"] == nil { vals["sum_rain_1"] = vals["Rain"] ?? nil }
        }
        // Pressure is reported by the base station but belongs to the exterior set.
        if let pressure = station?.dashboardData?["Pressure"]?.doubleValue {
            vals["Pressure"] = pressure
        }
        return vals
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    stationHeader
                    if let err = error {
                        Text(err)
                            .font(.caption).foregroundStyle(.red).padding()
                    }
                    LazyVStack(spacing: 20) {
                        if station != nil {
                            exteriorSection
                            interiorSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Estación Meteorológica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button(action: { Task { await loadAll() } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { await loadAll() }
            .task { await loadAll() }
        }
    }

    // MARK: - Header

    private var stationHeader: some View {
        let cfg = AppConfiguration.shared
        let name = station?.stationName ?? cfg.stationLocation
        let reachable = station?.reachable ?? false
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                if !name.isEmpty { Text(name).font(.headline) }
                if !cfg.stationLocation.isEmpty {
                    Text(cfg.stationLocation).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(reachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (reachable ? Color.green : Color.red).opacity(0.4), radius: 4)
                Text(reachable ? "Online" : "Offline").font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding()
        .background(AppTheme.heroGradient)
        .foregroundStyle(.white)
    }

    // MARK: - Sections

    /// Battery lives on the module, not on the measurement: the outdoor sensor powers
    /// temperature/humidity and the gauge powers the rain tiles. Pressure comes from the
    /// mains-powered base station, so it gets no indicator.
    /// One badge per physical module, on its headline tile: the outdoor sensor is read on
    /// Temperature and the gauge on Lluvia. Pressure comes from the mains-powered base.
    private var exteriorBatteries: [String: Int] {
        var b: [String: Int] = [:]
        if let p = exteriorModule?.batteryPercent { b["Temperature"] = p }
        if let p = rainModule?.batteryPercent { b["sum_rain_1"] = p }
        return b
    }

    private var exteriorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Exterior", timestamp: station?.lastStatusStore)
            MetricCardsGrid(values: exteriorValues, batteries: exteriorBatteries)
            if let note = rainNote {
                Label(LocalizedStringKey(note), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The rain gauge is the module that fails silently: when it is out of range or
    /// out of battery the whole tile just disappears and it looks like it never rains.
    private var rainNote: String? {
        let cfg = AppConfiguration.shared
        if cfg.moduleRain.isEmpty {
            return station == nil ? nil : "No hay pluviómetro detectado. Pulsa «Detectar de nuevo» en Ajustes."
        }
        guard let rainModule else { return "El pluviómetro configurado ya no está en la estación." }
        if rainModule.reachable == false || (rainModule.dashboardData?.isEmpty ?? true) {
            return "El pluviómetro no envía datos (sin cobertura o sin pilas)."
        }
        return nil
    }

    private var interiorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Interior", timestamp: station?.lastStatusStore)
            MetricCardsGrid(values: interiorValues, batteries: [:])
        }
    }

    private func sectionHeader(_ title: String, timestamp: Int?) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.caption).fontWeight(.bold).textCase(.uppercase)
                .foregroundStyle(.secondary).tracking(1.5)
            if let ts = timestamp {
                Text("· " + formatTimestamp(ts))
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.58, green: 0.67, blue: 0.75))
            }
        }
    }

    private func formatTimestamp(_ ts: Int) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        f.locale = Locale(identifier: "es_ES")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    // MARK: - Load

    private func loadAll() async {
        let cfg = AppConfiguration.shared
        guard cfg.isNetatmoConfigured else {
            error = "Configura Netatmo en Ajustes"
            return
        }
        isLoading = true
        error = nil

        do {
            let resp = try await NetatmoService.shared.getStationsData()
            let devices = resp.body?.devices ?? []

            if let main = devices.first(where: { $0.id == cfg.deviceId }) ?? devices.first {
                station = main
                let mods = main.modules ?? []
                exteriorModule = mods.first(where: { $0.id == cfg.moduleExterior })
                    ?? mods.first(where: { $0.type == "NAModule1" })
                rainModule = mods.first(where: { $0.id == cfg.moduleRain })
                    ?? mods.first(where: { $0.type == "NAModule3" })
            }
        } catch let e {
            error = e.localizedDescription
        }

        if let station {
            // The station physically lives in La Granja — tag the snapshot with its
            // coords so the weather widget shows it only when configured for that town.
            let st = LocationStore.shared.locations.first {
                $0.name.lowercased().contains("granja")
            } ?? SavedLocation.defaults[0]
            WidgetStore.save(netatmo: NetatmoSnapshotBuilder.make(
                station: station, exterior: exteriorModule, rain: rainModule,
                name: cfg.stationLocation, lat: st.lat, lon: st.lon))
        }

        isLoading = false
    }
}

// MARK: - Metric Cards Grid

struct MetricCardsGrid: View {
    let values: [String: Double?]
    /// Battery level of the module behind each metric, when it runs on batteries.
    var batteries: [String: Int] = [:]

    private let typeMeta: [(key: String, label: String, unit: String, icon: String, color: Color)] = [
        ("Temperature", "Temperatura", "°C",   "thermometer.medium",    .orange),
        ("Humidity",    "Humedad",     "%",     "humidity.fill",          .blue),
        ("Pressure",    "Presión",     " hPa",  "gauge.medium",           AppTheme.green),
        ("CO2",         "CO₂",         " ppm",  "aqi.medium",             .purple),
        ("Noise",       "Ruido",       " dB",   "speaker.wave.2.fill",    .gray),
        // The headline number is the last hour, not `Rain`: that field is only the last
        // 5-minute bucket, so with light rain it reads 0,0 and the station looks dry.
        // Today's total rides along in the corner instead of taking its own tile.
        ("sum_rain_1",  "Lluvia 1h",   " L/m²", "cloud.rain.fill",        .indigo),
    ]

    var body: some View {
        // Compact 2-up grid so a full station (4 exterior + 4 interior = 8 tiles) fits without scrolling.
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(typeMeta, id: \.key) { meta in
                if let val = values[meta.key] {
                    MetricCard(label: meta.label, unit: meta.unit,
                               icon: meta.icon, color: meta.color,
                               value: val, metaKey: meta.key,
                               battery: batteries[meta.key],
                               today: meta.key == "sum_rain_1" ? (values["sum_rain_24"] ?? nil) : nil)
                }
            }
        }
    }
}

struct MetricCard: View {
    let label: String
    let unit: String
    let icon: String
    let color: Color
    let value: Double?
    let metaKey: String
    /// `nil` for mains-powered sensors (the base station), so they show no indicator.
    var battery: Int? = nil
    /// Rain only: today's accumulation, tucked in the corner next to the hourly figure.
    var today: Double? = nil

    private var isRain: Bool { metaKey == "Rain" || metaKey.hasPrefix("sum_rain") }

    private var displayValue: String {
        guard let v = value else { return "—" }
        if isRain { return MetricCard.rain(v) }
        if v == v.rounded() && metaKey != "Temperature" { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }

    /// Rain always keeps its decimal: 0,2 L/m² is a real reading and "0" would hide it.
    private static func rain(_ v: Double) -> String {
        rainFormatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Built once: NumberFormatter is expensive and these cards redraw on every refresh.
    private static let rainFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .autoupdatingCurrent
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    /// The badge is silent to VoiceOver on its own, so the level is spoken with the reading.
    private var spokenValue: Text {
        var parts = [value == nil ? "—" : displayValue + unit]
        // `String(localized:)` on purpose: interpolating a String into `Text` picks the
        // non-localizing overload, and the wording would never reach the catalog.
        if let t = today { parts.append(String(localized: "hoy \(MetricCard.rain(t) + unit)")) }
        if let b = battery { parts.append(String(localized: "batería \(b) %")) }
        return Text(verbatim: parts.joined(separator: ", "))
    }

    /// Four bars, one per quarter of charge — the count is the reading and the colour
    /// only underlines it, so it still works without seeing colour.
    private var batteryBars: Int {
        guard let b = battery else { return 0 }
        switch b {
        case 76...: return 4
        case 51...: return 3
        case 26...: return 2
        default:    return 1
        }
    }

    private var batteryColor: Color {
        switch batteryBars {
        case 4, 3: return AppTheme.green
        case 2:    return AppTheme.sun
        default:   return .red
        }
    }

    @ViewBuilder
    private var batteryBadge: some View {
        if battery != nil {
            HStack(spacing: 1.5) {
                ForEach(1...4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(i <= batteryBars ? batteryColor : Color(.systemGray5))
                        .frame(width: 2.5, height: 9)
                }
            }
            .padding(.top, 8).padding(.trailing, 8)
        }
    }

    /// "hoy 4,2" — today's total, small, so the tile keeps one headline number.
    @ViewBuilder
    private var todayBadge: some View {
        if let t = today {
            // `String(localized:)`: interpolating a String straight into `Text` picks the
            // non-localizing overload and the word would never reach the catalog.
            Text(String(localized: "hoy \(MetricCard.rain(t))"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 7).padding(.leading, 8)
        }
    }

    private var pressureIcon: String {
        guard metaKey == "Pressure", let v = value else { return icon }
        if v >= 1023 { return "sun.max.fill" }
        if v >= 1010 { return "cloud.sun.fill" }
        if v >= 1000 { return "cloud.fill" }
        if v >= 990  { return "cloud.drizzle.fill" }
        return "cloud.bolt.fill"
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: metaKey == "Pressure" ? pressureIcon : icon)
                .font(.title3).foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12))
                .clipShape(Circle())
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(displayValue)
                    .font(.system(size: 25, weight: .heavy)).foregroundStyle(color)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11).padding(.horizontal, 10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) { batteryBadge }
        .overlay(alignment: .topLeading) { todayBadge }
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(AppTheme.green.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
        .accessibilityValue(spokenValue)
    }
}
