import SwiftUI

struct ActualView: View {
    @State private var station: NetatmoDevice?
    @State private var exteriorModule: NetatmoModule?
    @State private var rainModule: NetatmoModule?
    @State private var windInfo: WindInfo?
    @State private var favorites: [FavoriteInfo] = []
    @State private var isLoading = false
    @State private var error: String?

    private var interiorValues: [String: Double?] {
        guard let data = station?.dashboardData else { return [:] }
        return Dictionary(uniqueKeysWithValues: data.map { ($0.key, $0.value.doubleValue) })
    }

    private var exteriorValues: [String: Double?] {
        var vals: [String: Double?] = [:]
        if let data = exteriorModule?.dashboardData {
            for (k, v) in data { vals[k] = v.doubleValue }
        }
        if let data = rainModule?.dashboardData {
            for (k, v) in data { vals[k] = v.doubleValue }
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
                        if !favorites.isEmpty {
                            favoritesSection
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
        .background(
            LinearGradient(colors: [Color(red: 0.12, green: 0.23, blue: 0.37),
                                    Color(red: 0.15, green: 0.39, blue: 0.92)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .foregroundStyle(.white)
    }

    // MARK: - Sections

    private var exteriorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Exterior", timestamp: station?.lastStatusStore)
            MetricCardsGrid(values: exteriorValues, windInfo: windInfo)
        }
    }

    private var interiorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Interior", timestamp: station?.lastStatusStore)
            MetricCardsGrid(values: interiorValues, windInfo: nil)
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Estaciones")
                .font(.caption).fontWeight(.bold).textCase(.uppercase)
                .foregroundStyle(.secondary).tracking(1.5)
            ForEach(favorites) { fav in FavoriteCard(info: fav) }
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

        // Start wind fetch in parallel with stations
        let windTask: Task<WindInfo?, Never>? = (cfg.windEnabled && cfg.windBbox != nil) ? Task {
            guard let bbox = cfg.windBbox,
                  let resp = try? await NetatmoService.shared.getPublicData(
                      neLat: bbox.neLat, neLon: bbox.neLon,
                      swLat: bbox.swLat, swLon: bbox.swLon)
            else { return nil }
            let stations = resp.body ?? []
            let target = stations.first(where: { $0.id == cfg.windStationId }) ?? stations.first
            guard let measure = target?.measures?.values.first else { return nil }
            return WindInfo(speed: measure.windStrength,
                            angle: measure.windAngle,
                            gust: measure.gustStrength)
        } : nil

        do {
            let resp = try await NetatmoService.shared.getStationsData(getFavorites: true)
            let devices = resp.body?.devices ?? []

            if let main = devices.first(where: { $0.id == cfg.deviceId }) {
                station = main
                let mods = main.modules ?? []
                exteriorModule = mods.first(where: { $0.id == cfg.moduleExterior })
                    ?? mods.first(where: { $0.type == "NAModule1" })
                rainModule = mods.first(where: { $0.id == cfg.moduleRain })
                    ?? mods.first(where: { $0.type == "NAModule3" })
            }

            let favMap = cfg.favoriteCityNames
            if !favMap.isEmpty {
                favorites = devices
                    .filter { $0.id != cfg.deviceId }
                    .compactMap { device -> FavoriteInfo? in
                        let city = device.place?.city ?? ""
                        let name = favMap[city.lowercased()] ?? city
                        guard !name.isEmpty else { return nil }
                        return makeFavoriteInfo(device, name: name)
                    }
            }
        } catch let e {
            error = e.localizedDescription
        }

        windInfo = await windTask?.value
        isLoading = false
    }

    private func makeFavoriteInfo(_ device: NetatmoDevice, name: String) -> FavoriteInfo {
        let mods = device.modules ?? []
        let ext = mods.first(where: { $0.type == "NAModule1" })
        let wind = mods.first(where: { $0.type == "NAModule2" })
        let rain = mods.first(where: { $0.type == "NAModule3" })
        return FavoriteInfo(
            deviceId: device.id,
            name: name,
            city: device.place?.city ?? "—",
            altitude: device.place?.altitude,
            reachable: device.reachable ?? false,
            extTemp: ext?.dashboardData?["Temperature"]?.doubleValue,
            extHumidity: ext?.dashboardData?["Humidity"]?.doubleValue,
            windSpeed: wind?.dashboardData?["WindStrength"]?.intValue,
            windAngle: wind?.dashboardData?["WindAngle"]?.intValue,
            rain: rain?.dashboardData?["Rain"]?.doubleValue,
            pressure: device.dashboardData?["Pressure"]?.doubleValue
        )
    }
}

// MARK: - Wind info (local)

struct WindInfo {
    let speed: Int?
    let angle: Int?
    let gust: Int?
}

// MARK: - Favorite info (local)

struct FavoriteInfo: Identifiable {
    var id: String { deviceId }
    let deviceId: String
    let name: String
    let city: String
    let altitude: Int?
    let reachable: Bool
    let extTemp: Double?
    let extHumidity: Double?
    let windSpeed: Int?
    let windAngle: Int?
    let rain: Double?
    let pressure: Double?
}

// MARK: - Metric Cards Grid

struct MetricCardsGrid: View {
    let values: [String: Double?]
    let windInfo: WindInfo?

    private let typeMeta: [(key: String, label: String, unit: String, icon: String, color: Color)] = [
        ("Temperature", "Temperatura", "°C",   "thermometer.medium",    .orange),
        ("Humidity",    "Humedad",     "%",     "humidity.fill",          .blue),
        ("Pressure",    "Presión",     " hPa",  "gauge.medium",           .green),
        ("CO2",         "CO₂",         " ppm",  "aqi.medium",             .purple),
        ("Noise",       "Ruido",       " dB",   "speaker.wave.2.fill",    .gray),
        ("Rain",        "Lluvia",      " L/m²", "cloud.rain.fill",        .indigo),
    ]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(typeMeta, id: \.key) { meta in
                if let val = values[meta.key] {
                    MetricCard(label: meta.label, unit: meta.unit,
                               icon: meta.icon, color: meta.color,
                               value: val, metaKey: meta.key)
                }
            }
            if let w = windInfo, w.speed != nil {
                WindMetricCard(wind: w)
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
        VStack(spacing: 8) {
            Image(systemName: metaKey == "Pressure" ? pressureIcon : icon)
                .font(.title2).foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(displayValue)
                    .font(.system(size: 26, weight: .heavy)).foregroundStyle(color)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct WindMetricCard: View {
    let wind: WindInfo

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "wind")
                .font(.title2).foregroundStyle(.cyan)
                .frame(width: 46, height: 46)
                .background(Color.cyan.opacity(0.1))
                .clipShape(Circle())
            if let str = wind.speed {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(str)")
                        .font(.system(size: 26, weight: .heavy)).foregroundStyle(.cyan)
                    Text(" km/h").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Viento \(windDirection(wind.angle))")
                .font(.caption).foregroundStyle(.secondary)
            if let gust = wind.gust {
                Text("Racha \(gust) km/h")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 12)
        .background(Color(red: 0.94, green: 0.98, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Favorite Station Card

struct FavoriteCard: View {
    let info: FavoriteInfo

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(info.name).font(.subheadline).fontWeight(.bold)
                        if !info.reachable {
                            Text("offline").font(.caption2).foregroundStyle(.red)
                        }
                    }
                    Text("\(info.city) · \(info.altitude.map { "\($0) m" } ?? "?")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                favCell("Exterior", extTemp: info.extTemp, extHum: info.extHumidity)
                favCell("Viento", windSpeed: info.windSpeed, windAngle: info.windAngle)
                favCell("Lluvia", rain: info.rain)
                favCell("Presión", pressure: info.pressure)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .opacity(info.reachable ? 1 : 0.5)
    }

    private func favCell(_ title: String,
                         extTemp: Double? = nil, extHum: Double? = nil,
                         windSpeed: Int? = nil, windAngle: Int? = nil,
                         rain: Double? = nil, pressure: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2).fontWeight(.bold).textCase(.uppercase)
                .foregroundStyle(.secondary).tracking(1)
            Group {
                if let t = extTemp {
                    Text(String(format: "%.1f °C", t))
                        .font(.title3).fontWeight(.heavy)
                    if let h = extHum {
                        Text("💧 \(Int(h)) %").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let s = windSpeed {
                    Text("\(s) km/h").font(.title3).fontWeight(.heavy)
                    Text("Dir: \(windDirection(windAngle))").font(.caption).foregroundStyle(.secondary)
                } else if let r = rain {
                    Text(String(format: "%.1f L/m²", r)).font(.title3).fontWeight(.heavy)
                } else if let p = pressure {
                    Text("\(Int(p)) hPa").font(.title3).fontWeight(.heavy)
                } else {
                    Text("—").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
