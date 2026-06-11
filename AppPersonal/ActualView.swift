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

    private var exteriorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Exterior", timestamp: station?.lastStatusStore)
            MetricCardsGrid(values: exteriorValues)
        }
    }

    private var interiorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Interior", timestamp: station?.lastStatusStore)
            MetricCardsGrid(values: interiorValues)
        }
    }

    private func sectionHeader(_ title: String, timestamp: Int?) -> some View {
        HStack {
            Text(title)
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

        if station != nil {
            let ext = exteriorValues
            // The station physically lives in La Granja — tag the snapshot with its
            // coords so a widget shows it only when configured for that town.
            let st = LocationStore.shared.locations.first {
                $0.name.lowercased().contains("granja")
            } ?? SavedLocation.defaults[0]
            WidgetStore.save(netatmo: NetatmoSnapshot(
                stationName: cfg.stationLocation,
                temperature: ext["Temperature"] ?? nil,
                humidity: ext["Humidity"] ?? nil,
                pressure: ext["Pressure"] ?? nil,
                date: Date(),
                lat: st.lat,
                lon: st.lon
            ))
        }

        isLoading = false
    }
}

// MARK: - Metric Cards Grid

struct MetricCardsGrid: View {
    let values: [String: Double?]

    private let typeMeta: [(key: String, label: String, unit: String, icon: String, color: Color)] = [
        ("Temperature", "Temperatura", "°C",   "thermometer.medium",    .orange),
        ("Humidity",    "Humedad",     "%",     "humidity.fill",          .blue),
        ("Pressure",    "Presión",     " hPa",  "gauge.medium",           AppTheme.green),
        ("CO2",         "CO₂",         " ppm",  "aqi.medium",             .purple),
        ("Noise",       "Ruido",       " dB",   "speaker.wave.2.fill",    .gray),
        ("Rain",        "Lluvia",      " L/m²", "cloud.rain.fill",        .indigo),
    ]

    var body: some View {
        // Compact 2-up grid so a full station (4 exterior + 4 interior = 8 tiles) fits without scrolling.
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(typeMeta, id: \.key) { meta in
                if let val = values[meta.key] {
                    MetricCard(label: meta.label, unit: meta.unit,
                               icon: meta.icon, color: meta.color,
                               value: val, metaKey: meta.key)
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

    private var displayValue: String {
        guard let v = value else { return "—" }
        if v == v.rounded() && metaKey != "Temperature" { return "\(Int(v))" }
        return String(format: "%.1f", v)
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
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11).padding(.horizontal, 10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(AppTheme.green.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
