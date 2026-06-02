import SwiftUI
import CoreLocation

struct AemetView: View {
    @State private var selectedLocation = "madrid"
    @State private var customMunicipio: String? = nil
    @State private var customDisplayName = ""
    @State private var searchText = ""
    @State private var searchResults: [AemetMunicipio] = []
    @State private var cachedMunicipios: [AemetMunicipio] = []
    @State private var showSearch = false
    @State private var daily: AemetDailyRoot? = nil
    @State private var hourly: AemetHourlyRoot? = nil
    @State private var obs: [AemetObservationRecord]? = nil
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var lastLoadedAt: Date? = nil
    @State private var searchDebounce: Task<Void, Never>? = nil

    private var locationName: String {
        customMunicipio != nil ? customDisplayName
            : (aemetPresetLocations.first { $0.key == selectedLocation }?.name ?? selectedLocation)
    }
    private var shortLocationName: String {
        locationName.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? locationName
    }
    private var locationIdema: String? {
        customMunicipio == nil ? aemetPresetLocations.first { $0.key == selectedLocation }?.idema : nil
    }
    private var locationIdemaName: String? {
        customMunicipio == nil ? aemetPresetLocations.first { $0.key == selectedLocation }?.idemaName : nil
    }
    private var currentMunicipio: String {
        customMunicipio ?? aemetPresetMunicipios[selectedLocation] ?? selectedLocation
    }
    private var hasData: Bool { daily != nil || hourly != nil || obs != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    searchBar
                    if let err = loadError { staleBanner(err) }
                    if isLoading && !hasData {
                        ProgressView().padding(32)
                    } else if hasData {
                        aemetContent()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .navigationTitle(shortLocationName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Picker("", selection: $selectedLocation) {
                        ForEach(aemetPresetLocations) { loc in
                            Text(loc.name).tag(loc.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedLocation) { _, _ in
                        customMunicipio = nil
                        customDisplayName = ""
                        searchText = ""
                        Task { await loadForecast() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Button { Task { await loadForecast() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: geolocate) {
                        Image(systemName: "location")
                    }
                }
            }
            .task { await loadForecast() }
            .refreshable { await loadForecast() }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Buscar municipio…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchText) { _, newVal in
                    if newVal.count < 2 { searchResults = []; showSearch = false; return }
                    searchDebounce?.cancel()
                    searchDebounce = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await performSearch(newVal)
                    }
                }
            if showSearch {
                VStack(spacing: 0) {
                    ForEach(searchResults) { result in
                        Button {
                            customMunicipio = result.codMunicipio
                            customDisplayName = "\(result.nombre)\(result.nombreProv.map { " · \($0)" } ?? "")"
                            searchText = customDisplayName
                            showSearch = false
                            Task { await loadForecast() }
                        } label: {
                            HStack {
                                Text(result.nombre).fontWeight(.semibold).foregroundStyle(.primary)
                                Spacer()
                                Text(result.nombreProv ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        Divider()
                    }
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func aemetContent() -> some View {
        let allFailed = daily == nil && hourly == nil && obs == nil
        if allFailed {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle).foregroundStyle(.orange)
                Text("AEMET no disponible").font(.headline)
                Text("Inténtalo en unos minutos con ↻.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24).frame(maxWidth: .infinity)
            .background(Color(red: 1.0, green: 0.98, blue: 0.88))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            nowCard()
            hourlyCard()
            dailyCard()
            todayDetailsCard()
            observationCard()
            sourceCard()
        }
    }

    // MARK: - Now card

    private func nowCard() -> some View {
        let today = daily?.prediccion?.dia?.first
        let hourlyDay = hourly?.prediccion?.dia?.first
        let lastObs = obs?.last
        let currentTemp = lastObs?.ta
        let tMax = today?.temperatura?.maxima
        let tMin = today?.temperatura?.minima
        let nowHour = Calendar.current.component(.hour, from: Date())
        let skyCode = hourlyDay?.estadoCielo?.first(where: { Int($0.periodo ?? "") == nowHour })?.value
            ?? hourlyDay?.estadoCielo?.first?.value
        let skyDesc = hourlyDay?.estadoCielo?.first(where: { Int($0.periodo ?? "") == nowHour })?.descripcion
            ?? hourlyDay?.estadoCielo?.first?.descripcion ?? "—"
        let windKmh = lastObs?.vv.map { Int($0 * 3.6) }
        let gustKmh = lastObs?.vmax.map { Int($0 * 3.6) }

        return HStack(spacing: 16) {
            WeatherIconView(code: skyCode).frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(currentTemp.map { "\(Int($0.rounded()))°" } ?? (tMax.map { "\(Int($0.rounded()))°" } ?? "—"))
                    .font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.white)
                Text(skyDesc).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 8) {
                    if let mx = tMax { Text("↑\(Int(mx.rounded()))°").foregroundStyle(.white) }
                    if let mn = tMin { Text("↓\(Int(mn.rounded()))°").foregroundStyle(.white.opacity(0.7)) }
                    if let hum = lastObs?.hr { Text("💧\(Int(hum))%").foregroundStyle(.white.opacity(0.85)) }
                }
                .font(.footnote)
                HStack(spacing: 8) {
                    if let w = windKmh { Text("💨 \(w) km/h").foregroundStyle(.white.opacity(0.85)) }
                    if let g = gustKmh, g > 0 { Text("racha \(g)").foregroundStyle(.white.opacity(0.7)) }
                    if let rain = lastObs?.prec, rain > 0 { Text("🌧 \(rain) L").foregroundStyle(.white.opacity(0.85)) }
                }
                .font(.footnote)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity).padding(16)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.23, blue: 0.37),
                                            Color(red: 0.15, green: 0.39, blue: 0.92)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 0.12, green: 0.23, blue: 0.37).opacity(0.3), radius: 8, y: 4)
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75)).textCase(.uppercase)
            Text(value).font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Hourly card

    private struct HourEntry: Identifiable {
        let id = UUID()
        let hour: Int; let date: String; let temp: Double; let skyCode: String?; let prob: Int?
    }

    private func buildHourlyEntries() -> [HourEntry] {
        var result: [HourEntry] = []
        let days = hourly?.prediccion?.dia ?? []
        let now = Date()
        let cal = Calendar.current
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        let nowFloor = cal.date(bySettingHour: cal.component(.hour, from: now), minute: 0, second: 0, of: now)!
        let cutoff = now.addingTimeInterval(48 * 3600)

        for day in days {
            let dayStr = String((day.fecha ?? "").prefix(10))
            guard let dayDate = isoFmt.date(from: dayStr) else { continue }
            for tEntry in (day.temperatura ?? []) {
                guard let hour = Int(tEntry.periodo ?? ""),
                      let temp = Double(tEntry.value ?? ""),
                      let entryDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: dayDate),
                      entryDate >= nowFloor && entryDate <= cutoff
                else { continue }
                let sky = day.estadoCielo?.first(where: { Int($0.periodo ?? "") == hour })?.value
                let probStr = day.probPrecipitacion?.first(where: { p in
                    guard let per = p.periodo, per.count == 4 else { return false }
                    let s = Int(per.prefix(2)) ?? 0; let e = Int(per.suffix(2)) ?? 0
                    return hour >= s && hour < e
                })?.value
                result.append(HourEntry(hour: hour, date: dayStr, temp: temp, skyCode: sky,
                                        prob: probStr.flatMap { Int($0) }))
            }
        }
        return result
    }

    @ViewBuilder
    private func hourlyCard() -> some View {
        let cards = buildHourlyEntries()
        if !cards.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("Próximas 48 horas")
                        .font(.caption).fontWeight(.bold).textCase(.uppercase)
                        .foregroundStyle(.secondary).tracking(1)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cards) { c in hourCell(c) }
                    }
                    .padding(14)
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private func hourCell(_ c: HourEntry) -> some View {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        let dayDate = isoFmt.date(from: c.date)
        let isToday = dayDate.map { Calendar.current.isDateInToday($0) } ?? false
        let label: String
        if isToday {
            label = String(format: "%02dh", c.hour)
        } else {
            let df = DateFormatter()
            df.locale = Locale(identifier: "es_ES")
            df.dateFormat = "EEE"
            let dayName = dayDate.map { df.string(from: $0) } ?? ""
            label = "\(dayName) \(String(format: "%02d", c.hour))h"
        }
        return VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            WeatherIconView(code: c.skyCode).frame(width: 36, height: 36)
            Text("\(Int(c.temp.rounded()))°").font(.subheadline).fontWeight(.bold)
            if let p = c.prob, p > 0 {
                Text("💧\(p)%").font(.caption2).foregroundStyle(.blue)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Daily card

    @ViewBuilder
    private func dailyCard() -> some View {
        let days = daily?.prediccion?.dia ?? []
        if !days.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("Próximos 7 días")
                        .font(.caption).fontWeight(.bold).textCase(.uppercase)
                        .foregroundStyle(.secondary).tracking(1)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    dailyRow(day, isFirst: i == 0)
                    if i < days.count - 1 { Divider() }
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private func dailyRow(_ day: AemetDailyDay, isFirst: Bool) -> some View {
        let sky = pickPeriod(day.estadoCielo)
        let probVal = maxOfDay(day.probPrecipitacion)?.value.flatMap { Int($0) }
        return HStack(spacing: 10) {
            Text(dayLabel(day.fecha, isFirst: isFirst))
                .font(.subheadline).fontWeight(.semibold).frame(width: 90, alignment: .leading)
            WeatherIconView(code: sky?.value).frame(width: 36, height: 36)
            HStack(spacing: 4) {
                Text(day.temperatura?.maxima.map { "\(Int($0.rounded()))°" } ?? "—")
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(.orange)
                Text(day.temperatura?.minima.map { "\(Int($0.rounded()))°" } ?? "—")
                    .font(.subheadline).foregroundStyle(.blue)
            }
            Spacer()
            HStack(spacing: 8) {
                if let p = probVal, p > 0 { Text("💧\(p)%").font(.caption).foregroundStyle(.blue) }
                if let u = day.uvMax, u > 0 { Text("☀️UV\(u)").font(.caption).foregroundStyle(.orange) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Today details card

    @ViewBuilder
    private func todayDetailsCard() -> some View {
        if let today = daily?.prediccion?.dia?.first {
            let t = today.temperatura
            let st = today.sensTermica
            let hr = today.humedadRelativa
            let viento = today.viento?.first(where: { $0.periodo == "00-24" }) ?? today.viento?.first
            let racha = maxOfDay(today.rachaMax)
            let prob = maxOfDay(today.probPrecipitacion)
            let cota = today.cotaNieveProv?.first(where: { $0.value != nil && $0.value != "" })

            VStack(spacing: 0) {
                HStack {
                    Text("Detalles de hoy")
                        .font(.caption).fontWeight(.bold).textCase(.uppercase)
                        .foregroundStyle(.secondary).tracking(1)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                if let t {
                    detailRow("Temperatura",
                              value: "\(t.minima.map { "\(Int($0.rounded()))°" } ?? "—") / \(t.maxima.map { "\(Int($0.rounded()))°" } ?? "—")")
                }
                if let st {
                    detailRow("Sensación térmica",
                              value: "\(st.minima.map { "\(Int($0.rounded()))°" } ?? "—") / \(st.maxima.map { "\(Int($0.rounded()))°" } ?? "—")")
                }
                if let hr {
                    detailRow("Humedad relativa",
                              value: "\(hr.minima.map { "\(Int($0.rounded()))%" } ?? "—") / \(hr.maxima.map { "\(Int($0.rounded()))%" } ?? "—")")
                }
                if let p = prob, let pv = p.value, !pv.isEmpty, pv != "0" {
                    detailRow("Prob. lluvia", value: "\(pv)%")
                }
                if let c = cota, let cv = c.value, !cv.isEmpty {
                    detailRow("Cota de nieve", value: "\(cv) m")
                }
                if let v = viento, let vel = v.velocidad, !vel.isEmpty {
                    detailRow("Viento", value: "\(v.direccion ?? "") \(vel) km/h")
                }
                if let r = racha, let rv = r.value, !rv.isEmpty {
                    detailRow("Racha máxima", value: "\(rv) km/h")
                }
                if let u = today.uvMax, u > 0 {
                    detailRow("Índice UV máximo", value: "\(u)")
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Observation card

    @ViewBuilder
    private func observationCard() -> some View {
        if let lastObs = obs?.last {
            let stName = lastObs.ubi ?? locationIdemaName ?? locationIdema ?? "Estación"
            VStack(spacing: 0) {
                HStack {
                    Text("Estación · \(stName)")
                        .font(.caption).fontWeight(.bold).textCase(.uppercase)
                        .foregroundStyle(.secondary).tracking(1)
                    Spacer()
                    if let id = locationIdema {
                        Text(id).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                if let fint = lastObs.fint, let date = ISO8601DateFormatter().date(from: fint) {
                    detailRow("Lectura", value: shortDateTime(date))
                }
                if let ta = lastObs.ta { detailRow("Temperatura", value: String(format: "%.1f°", ta)) }
                if lastObs.tamin != nil || lastObs.tamax != nil {
                    detailRow("T min/máx",
                              value: "\(lastObs.tamin.map { String(format: "%.1f°", $0) } ?? "—") / \(lastObs.tamax.map { String(format: "%.1f°", $0) } ?? "—")")
                }
                if let hr = lastObs.hr { detailRow("Humedad", value: "\(Int(hr))%") }
                if let pres = lastObs.pres { detailRow("Presión", value: "\(pres) hPa") }
                if let vv = lastObs.vv { detailRow("Viento", value: String(format: "%d km/h", Int(vv * 3.6))) }
                if let vmax = lastObs.vmax, vmax > 0 {
                    detailRow("Racha máxima", value: String(format: "%d km/h", Int(vmax * 3.6)))
                }
                if let prec = lastObs.prec, prec > 0 {
                    detailRow("Precipitación (1h)", value: "\(prec) L/m²")
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Source card

    @ViewBuilder
    private func sourceCard() -> some View {
        if let origen = daily?.origen ?? hourly?.origen {
            VStack(alignment: .leading, spacing: 4) {
                if let elab = daily?.elaborado ?? hourly?.elaborado,
                   let date = ISO8601DateFormatter().date(from: elab) {
                    Text("Predicción: \(shortDateTime(date))").font(.caption).foregroundStyle(.secondary)
                }
                if let prod = origen.productor {
                    Text("Fuente: \(prod)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Stale / error banner

    private func staleBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Detail row

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.bold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(Divider().padding(.leading, 16), alignment: .top)
    }

    // MARK: - Helpers

    private func shortDateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func dayLabel(_ fecha: String?, isFirst: Bool) -> String {
        guard let fecha else { return "—" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        guard let date = f.date(from: String(fecha.prefix(10))) else { return fecha }
        if isFirst && Calendar.current.isDateInToday(date) { return "Hoy" }
        let df = DateFormatter(); df.locale = Locale(identifier: "es_ES"); df.dateFormat = "EEEE d MMM"
        return df.string(from: date).capitalized
    }

    private func pickPeriod(_ arr: [AemetPeriodValue]?) -> AemetPeriodValue? {
        guard let arr else { return nil }
        for p in ["00-24", "12-24", "06-24"] {
            if let m = arr.first(where: { $0.periodo == p && ($0.value ?? "").isEmpty == false }) { return m }
        }
        return arr.first(where: { ($0.value ?? "").isEmpty == false }) ?? arr.first
    }

    private func maxOfDay(_ arr: [AemetPeriodValue]?) -> AemetPeriodValue? {
        arr?.max(by: { (Double($0.value ?? "") ?? 0) < (Double($1.value ?? "") ?? 0) })
    }

    // MARK: - Search

    private func performSearch(_ query: String) async {
        if cachedMunicipios.isEmpty {
            cachedMunicipios = (try? await AEMETService.shared.allMunicipios()) ?? []
        }
        let q = query.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        searchResults = Array(
            cachedMunicipios
                .filter { $0.nombre.lowercased().folding(options: .diacriticInsensitive, locale: .current).contains(q) }
                .prefix(10)
        )
        showSearch = !searchResults.isEmpty
    }

    // MARK: - Networking

    private func loadForecast() async {
        guard AppConfiguration.shared.isAemetConfigured else { return }
        isLoading = true
        loadError = nil
        let municipio = currentMunicipio
        let idema = locationIdema

        // All three calls run in parallel
        async let dResult = AEMETService.shared.forecastDaily(municipio: municipio)
        async let hResult = AEMETService.shared.forecastHourly(municipio: municipio)
        let obsTask = idema.map { id in
            Task<[AemetObservationRecord]?, Never> {
                try? await AEMETService.shared.observation(idema: id)
            }
        }

        var newDaily: AemetDailyRoot? = nil
        var newHourly: AemetHourlyRoot? = nil
        var dailyErr: String? = nil
        var hourlyErr: String? = nil

        do { newDaily  = try await dResult  } catch { dailyErr  = error.localizedDescription }
        do { newHourly = try await hResult  } catch { hourlyErr = error.localizedDescription }
        let newObs = await obsTask?.value

        if newDaily != nil || newHourly != nil {
            daily  = newDaily  ?? daily
            hourly = newHourly ?? hourly
            obs    = newObs    ?? obs
            lastLoadedAt = Date()
        } else if daily != nil || hourly != nil {
            loadError = "AEMET sin respuesta · datos anteriores"
        } else {
            let detail = dailyErr ?? hourlyErr ?? "sin respuesta"
            loadError = "AEMET no disponible: \(detail)"
        }
        isLoading = false
    }

    private func geolocate() {
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        guard let loc = mgr.location else { return }
        let coord = loc.coordinate
        let nearest = sunMoonLocations.min(by: { a, b in
            let da = pow(a.lat - coord.latitude, 2) + pow(a.lon - coord.longitude, 2)
            let db = pow(b.lat - coord.latitude, 2) + pow(b.lon - coord.longitude, 2)
            return da < db
        })
        if let n = nearest {
            selectedLocation = n.key
            customMunicipio = nil
            customDisplayName = ""
            searchText = ""
            Task { await loadForecast() }
        }
    }
}

// MARK: - Weather SF Symbol Icon

struct WeatherIconView: View {
    let code: String?

    private var category: String {
        guard let code else { return "unknown" }
        let isNight = code.hasSuffix("n")
        let n = Int(code.filter { $0.isNumber }) ?? 0
        switch n {
        case 11: return isNight ? "clear-n" : "clear"
        case 12, 13: return isNight ? "partly-n" : "partly"
        case 14, 15, 16: return "cloudy"
        case 17: return "high-clouds"
        case 23...26: return "rain"
        case 33...36: return "snow"
        case 43...46: return "shower"
        case 51...54: return "thunder"
        case 61...64: return "thunder-rain"
        case 71...74: return "light-snow"
        case 81: return "fog"
        case 82, 83: return "mist"
        default: return "unknown"
        }
    }

    private var sfSymbol: String {
        switch category {
        case "clear":         return "sun.max.fill"
        case "clear-n":       return "moon.stars.fill"
        case "partly":        return "cloud.sun.fill"
        case "partly-n":      return "cloud.moon.fill"
        case "cloudy":        return "cloud.fill"
        case "high-clouds":   return "smoke.fill"
        case "rain":          return "cloud.rain.fill"
        case "shower":        return "cloud.drizzle.fill"
        case "thunder":       return "cloud.bolt.fill"
        case "thunder-rain":  return "cloud.bolt.rain.fill"
        case "snow":          return "cloud.snow.fill"
        case "light-snow":    return "cloud.sleet.fill"
        case "fog":           return "cloud.fog.fill"
        case "mist":          return "cloud.fog"
        default:              return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch category {
        case "clear":                    return .yellow
        case "clear-n":                  return .indigo
        case "partly":                   return .orange
        case "partly-n":                 return .purple
        case "cloudy", "high-clouds":    return .gray
        case "rain", "shower":           return .blue
        case "thunder", "thunder-rain":  return .purple
        case "snow", "light-snow":       return .cyan
        case "fog", "mist":              return Color(.systemGray3)
        default:                         return .gray
        }
    }

    var body: some View {
        Image(systemName: sfSymbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(iconColor)
    }
}
