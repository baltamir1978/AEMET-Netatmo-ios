import SwiftUI
import CoreLocation
import Charts

struct AemetView: View {
    @ObservedObject private var store = LocationStore.shared
    @State private var showManage = false
    @State private var searchText = ""
    @State private var searchResults: [AemetMunicipio] = []
    @State private var cachedMunicipios: [AemetMunicipio] = []
    @State private var showSearch = false
    @State private var daily: AemetDailyRoot? = nil
    @State private var hourly: AemetHourlyRoot? = nil
    @State private var obs: [AemetObservationRecord]? = nil
    @State private var openMeteo: OpenMeteoData? = nil
    @State private var alerts: [AemetAlert] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var lastLoadedAt: Date? = nil
    @State private var searchDebounce: Task<Void, Never>? = nil

    /// Auto-refreshes (view appear, city switch) reuse cached AEMET data younger
    /// than this; only an explicit pull/tap forces a live request. Keeps us well
    /// under AEMET's request limits — forecasts only update a few times a day.
    private let aemetTTL: TimeInterval = 3 * 60 * 60
    /// Warnings are time-sensitive, so auto-refreshes accept fresher cache than the
    /// forecast. The CAP bundle is cached per CCAA, so cities sharing one reuse it.
    private let aemetAlertTTL: TimeInterval = 60 * 60

    private var locationName: String { store.selected.name }
    private var shortLocationName: String {
        locationName.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? locationName
    }
    private var locationIdema: String? { store.selected.idema }
    private var currentMunicipio: String { store.selected.code }
    private var hasData: Bool { daily != nil || hourly != nil || obs != nil }

    /// Coordinates of the selected location (used for Open-Meteo air/pollen/UV).
    private var coords: (lat: Double, lon: Double)? {
        (store.selected.lat, store.selected.lon)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    searchBar
                    if !alerts.isEmpty { alertsBanner }
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
                    Picker("", selection: $store.selectedCode) {
                        ForEach(store.pickerOptions) { loc in
                            Text(loc.isCurrent ? store.currentDisplayName : loc.name).tag(loc.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: store.selectedCode) { _, newCode in
                        store.select(newCode)
                        searchText = ""
                        Task { await loadForecast() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Button { Task { await loadForecast(force: true) } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: geolocate) {
                        Image(systemName: "location")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showManage = true } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
            .task { await loadForecast() }
            .refreshable { await loadForecast(force: true) }
            .sheet(isPresented: $showManage) {
                LocationManagerSheet { Task { await loadForecast() } }
            }
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
                            addLocation(result)
                        } label: {
                            HStack {
                                Text(result.nombre).fontWeight(.semibold).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(AppTheme.green)
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
            tempChartCard()
            airPollenUVCard()
            dailyCard()
            todayDetailsCard()
            observationCard()
            sourceCard()
            updatedFooter()
        }
    }

    /// Timestamp of the last successful fetch, shown at the very bottom of the screen.
    @ViewBuilder
    private func updatedFooter() -> some View {
        if let t = lastLoadedAt {
            HStack(spacing: 5) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath").font(.caption2)
                Text("Actualizado \(shortDateTime(t))").font(.caption2)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.top, 2).padding(.bottom, 6)
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

        return HStack(alignment: .top, spacing: 16) {
            WeatherIconView(code: skyCode).frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(currentTemp.map { "\(Int($0.rounded()))°" } ?? (tMax.map { "\(Int($0.rounded()))°" } ?? "—"))
                    .font(.system(size: 46, weight: .light)).foregroundStyle(.white)
                Text(skyDesc).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 8) {
                    if let mx = tMax { Text("↑\(Int(mx.rounded()))°").foregroundStyle(.white) }
                    if let mn = tMin { Text("↓\(Int(mn.rounded()))°").foregroundStyle(.white.opacity(0.7)) }
                }
                .font(.footnote)
            }
            Spacer(minLength: 8)
            // Right column fills the previously-empty space with the live readings.
            VStack(alignment: .trailing, spacing: 7) {
                if let hum = lastObs?.hr { heroStat("💧", "\(Int(hum))%", "Humedad") }
                if let w = windKmh {
                    heroStat("💨", "\(w) km/h", (gustKmh.map { $0 > 0 ? "racha \($0)" : "Viento" }) ?? "Viento")
                }
                if let rain = lastObs?.prec, rain > 0 { heroStat("🌧", "\(rain) L/m²", "Lluvia 1h") }
            }
        }
        .frame(maxWidth: .infinity).padding(16)
        .background(AppTheme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppTheme.greenDeep.opacity(0.3), radius: 8, y: 4)
    }

    /// Right-column readout in the hero card: emoji + value over a faint caption.
    private func heroStat(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 5) {
                Text(icon).font(.subheadline)
                Text(value).font(.title3).fontWeight(.bold).foregroundStyle(.white)
            }
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
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
            Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(.primary)
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

    // MARK: - Temperature chart (next hours, Breezy-style curve)

    @ViewBuilder
    private func tempChartCard() -> some View {
        let entries = buildHourlyEntries()
        if entries.count >= 3 {
            let indexed = Array(entries.enumerated())
            let temps = entries.map { $0.temp }
            let tMin = temps.min() ?? 0
            let tMax = temps.max() ?? 0
            let tickStep = max(1, entries.count / 6)
            // Precipitation-probability bars live in a band below the curve; `floor` is the
            // chart's lower bound and `barCeil` how high a 100%-probability bar reaches.
            let span = max(tMax - tMin, 1)
            let floor = tMin - span * 0.5
            let barCeil = tMin - span * 0.08
            let hasRain = entries.contains { ($0.prob ?? 0) > 0 }
            VStack(spacing: 0) {
                HStack {
                    Text("Temperatura próximas horas")
                        .font(.caption).fontWeight(.bold).textCase(.uppercase)
                        .foregroundStyle(.secondary).tracking(1)
                    Spacer()
                    HStack(spacing: 8) {
                        if hasRain {
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1).fill(.blue.opacity(0.35)).frame(width: 7, height: 9)
                                Text("lluvia").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text("\(Int(tMin.rounded()))° / \(Int(tMax.rounded()))°")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                Chart {
                    ForEach(indexed, id: \.offset) { i, e in
                        if let p = e.prob, p > 0 {
                            BarMark(x: .value("h", i),
                                    yStart: .value("base", floor),
                                    yEnd: .value("prob", floor + (barCeil - floor) * Double(p) / 100),
                                    width: .ratio(0.55))
                                .foregroundStyle(.blue.opacity(0.30))
                                .cornerRadius(2)
                        }
                        AreaMark(x: .value("h", i), yStart: .value("base", floor), yEnd: .value("°C", e.temp))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(
                                colors: [.orange.opacity(0.28), .orange.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("h", i), y: .value("°C", e.temp))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                }
                .chartYScale(domain: floor ... (tMax + span * 0.12))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            // Hide labels in the precip band so the axis reads only temperatures.
                            if let d = v.as(Double.self), d >= tMin - span * 0.05 {
                                Text("\(Int(d))°").font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: Array(stride(from: 0, to: entries.count, by: tickStep))) { idx in
                        AxisValueLabel {
                            if let i = idx.as(Int.self), i < entries.count {
                                Text(String(format: "%02dh", entries[i].hour)).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 138)
                .padding(.horizontal, 12).padding(.vertical, 12)
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
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
            let stName = lastObs.ubi ?? locationIdema ?? "Estación"
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

    // MARK: - Air quality / pollen / UV card (Open-Meteo)

    @ViewBuilder
    private func airPollenUVCard() -> some View {
        if let om = openMeteo {
            VStack(spacing: 0) {
                HStack {
                    Text("Aire · Polen · UV")
                        .font(.caption).fontWeight(.bold).textCase(.uppercase)
                        .foregroundStyle(.secondary).tracking(1)
                    Spacer()
                    Text("Open-Meteo").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider()

                // Top row: AQI + UV
                HStack(spacing: 12) {
                    if let aqi = om.aqi {
                        let band = OpenMeteoService.aqiBand(aqi)
                        airBadge(title: "Calidad aire", value: "\(aqi)",
                                 subtitle: band.label, color: severityColor(band.severity))
                    }
                    if let uv = om.uvMax ?? om.uvIndex {
                        airBadge(title: "Índice UV", value: "\(Int(uv.rounded()))",
                                 subtitle: uvLabel(uv), color: uvColor(uv), scale: "11")
                    }
                }
                .padding(.horizontal, 12).padding(.top, 12)

                if om.pm25 != nil || om.pm10 != nil {
                    HStack(spacing: 16) {
                        if let pm = om.pm25 { Text("PM2.5 \(Int(pm.rounded())) µg/m³").font(.caption).foregroundStyle(.secondary) }
                        if let pm = om.pm10 { Text("PM10 \(Int(pm.rounded())) µg/m³").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }

                if !om.pollen.isEmpty {
                    Divider().padding(.top, 12)
                    VStack(spacing: 6) {
                        ForEach(om.pollen) { p in
                            let lvl = OpenMeteoService.pollenLevel(p.value)
                            HStack {
                                Circle().fill(severityColor(lvl.severity)).frame(width: 8, height: 8)
                                Text(p.name).font(.subheadline)
                                Spacer()
                                Text(lvl.label).font(.caption).foregroundStyle(.secondary)
                                Text("\(Int(p.value.rounded())) gr/m³")
                                    .font(.caption).fontWeight(.semibold).monospacedDigit()
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                } else {
                    Color.clear.frame(height: 12)
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private func airBadge(title: String, value: String, subtitle: String, color: Color,
                          scale: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 30, weight: .heavy)).foregroundStyle(color)
                if let scale {
                    Text("/\(scale)").font(.caption).fontWeight(.semibold).foregroundStyle(color.opacity(0.65))
                }
            }
            Text(subtitle).font(.caption).fontWeight(.semibold).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func severityColor(_ s: Int) -> Color {
        switch s {
        case 0:  return AppTheme.green
        case 1:  return AppTheme.greenMid
        case 2:  return .yellow
        case 3:  return .orange
        case 4:  return .red
        default: return .purple
        }
    }

    private func uvLabel(_ uv: Double) -> String {
        switch uv {
        case ..<3:  return "Bajo"
        case ..<6:  return "Moderado"
        case ..<8:  return "Alto"
        case ..<11: return "Muy alto"
        default:    return "Extremo"
        }
    }

    private func uvColor(_ uv: Double) -> Color {
        switch uv {
        case ..<3:  return AppTheme.green
        case ..<6:  return .yellow
        case ..<8:  return .orange
        case ..<11: return .red
        default:    return .purple
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

    // MARK: - AEMET warnings

    @ViewBuilder private var alertsBanner: some View {
        VStack(spacing: 8) {
            ForEach(alerts) { a in
                HStack(spacing: 10) {
                    Image(systemName: a.sfSymbol)
                        .font(.title3).foregroundStyle(.white)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(a.phenomenon) · nivel \(a.level.name)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        if let win = alertWindow(a) {
                            Text(win).font(.caption).foregroundStyle(.white.opacity(0.9))
                        }
                        Text(a.areaDesc).font(.caption2).foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(a.badge.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// "Hoy 12:00 → mañana 09:00"-style window for a warning.
    private func alertWindow(_ a: AemetAlert) -> String? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "EEE HH:mm"
        switch (a.onset, a.expires) {
        case let (on?, ex?): return "\(df.string(from: on).capitalized) → \(df.string(from: ex).capitalized)"
        case let (on?, nil): return "desde \(df.string(from: on).capitalized)"
        case let (nil, ex?): return "hasta \(df.string(from: ex).capitalized)"
        default:             return nil
        }
    }

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

    /// Add a searched municipio to the followed list and select it.
    private func addLocation(_ m: AemetMunicipio) {
        let loc = SavedLocation(
            code: m.codMunicipio,
            name: m.nombre,
            province: nil,
            lat: m.lat ?? store.selected.lat,
            lon: m.lon ?? store.selected.lon,
            idema: nil
        )
        store.add(loc)
        searchText = ""
        searchResults = []
        showSearch = false
        Task { await loadForecast() }
    }

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

    private func loadForecast(force: Bool = false) async {
        guard AppConfiguration.shared.isAemetConfigured else { return }
        // Auto-refreshes reuse fresh cache; pull/tap forces a live request.
        let maxAge: TimeInterval? = force ? nil : aemetTTL
        isLoading = true
        loadError = nil
        // Resolve GPS → nearest municipio when the "current location" entry is active.
        if store.selectedCode == SavedLocation.currentCode {
            let ok = await store.resolveCurrent()
            if !ok && store.resolvedCurrent == nil {
                loadError = "No se pudo obtener tu ubicación. Revisa los permisos de localización."
                isLoading = false
                return
            }
        }
        let municipio = currentMunicipio
        let idema = locationIdema

        // All calls run in parallel
        async let dResult = AEMETService.shared.forecastDaily(municipio: municipio, maxAge: maxAge)
        async let hResult = AEMETService.shared.forecastHourly(municipio: municipio, maxAge: maxAge)
        let obsTask = idema.map { id in
            Task<[AemetObservationRecord]?, Never> {
                try? await AEMETService.shared.observation(idema: id, maxAge: maxAge)
            }
        }
        let omTask = coords.map { c in
            Task<OpenMeteoData?, Never> { await OpenMeteoService.shared.fetch(lat: c.lat, lon: c.lon) }
        }
        let alertTask = coords.map { c in
            Task<[AemetAlert], Never> {
                (try? await AEMETService.shared.alerts(
                    municipioCode: municipio, lat: c.lat, lon: c.lon,
                    maxAge: force ? nil : aemetAlertTTL)) ?? []
            }
        }

        var newDaily: AemetDailyRoot? = nil
        var newHourly: AemetHourlyRoot? = nil
        var dailyErr: String? = nil
        var hourlyErr: String? = nil

        do { newDaily  = try await dResult  } catch { dailyErr  = error.localizedDescription }
        do { newHourly = try await hResult  } catch { hourlyErr = error.localizedDescription }
        let newObs = await obsTask?.value
        openMeteo = await omTask?.value ?? openMeteo
        alerts = await alertTask?.value ?? alerts

        if newDaily != nil || newHourly != nil {
            daily  = newDaily  ?? daily
            hourly = newHourly ?? hourly
            obs    = newObs    ?? obs
            lastLoadedAt = Date()
            saveAemetSnapshot()
            Task { await refreshAllWidgetCities() }
        } else if daily != nil || hourly != nil {
            loadError = "AEMET sin respuesta · datos anteriores"
        } else {
            let detail = dailyErr ?? hourlyErr ?? "sin respuesta"
            loadError = "AEMET no disponible: \(detail)"
        }
        isLoading = false
    }

    /// Persist the selected city's AEMET forecast to the App Group (global key + keyed by code).
    private func saveAemetSnapshot() {
        let snap = Self.makeAemetSnapshot(municipio: locationName, daily: daily, hourly: hourly,
                                          alert: alerts.first?.badge)
        WidgetStore.save(aemet: snap)                       // global (legacy / "follow app" fallback)
        WidgetStore.save(aemet: snap, forCode: currentMunicipio)
    }

    /// Fetch & cache every followed city's forecast so a widget configured for any of
    /// them has data without the user opening that city. Throttled to ~20 min.
    private func refreshAllWidgetCities() async {
        let key = "widget.aemet.allCitiesRefreshedAt"
        let ud = UserDefaults.standard
        let last = ud.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 60 else { return }
        ud.set(Date(), forKey: key)

        for loc in store.locations where loc.code != currentMunicipio {
            async let d = try? await AEMETService.shared.forecastDaily(municipio: loc.code, maxAge: aemetTTL)
            async let h = try? await AEMETService.shared.forecastHourly(municipio: loc.code, maxAge: aemetTTL)
            let (dr, hr) = await (d, h)
            guard dr != nil || hr != nil else { continue }
            let cityAlert = (try? await AEMETService.shared.alerts(
                municipioCode: loc.code, lat: loc.lat, lon: loc.lon, maxAge: aemetAlertTTL))?.first?.badge
            let snap = Self.makeAemetSnapshot(municipio: loc.name, daily: dr, hourly: hr, alert: cityAlert)
            WidgetStore.save(aemet: snap, forCode: loc.code)
        }
        WidgetStore.reload()
    }

    /// Build a widget snapshot from forecast roots (pure — works for any city).
    static func makeAemetSnapshot(municipio: String,
                                  daily: AemetDailyRoot?,
                                  hourly: AemetHourlyRoot?,
                                  alert: AemetAlertBadge? = nil) -> AemetSnapshot {
        let today = daily?.prediccion?.dia?.first
        let hourlyDay = hourly?.prediccion?.dia?.first
        let nowHour = Calendar.current.component(.hour, from: Date())
        let skyCode = hourlyDay?.estadoCielo?.first(where: { Int($0.periodo ?? "") == nowHour })?.value
            ?? hourlyDay?.estadoCielo?.first?.value
        let skyDesc = hourlyDay?.estadoCielo?.first(where: { Int($0.periodo ?? "") == nowHour })?.descripcion
            ?? hourlyDay?.estadoCielo?.first?.descripcion ?? "—"
        let currentTemp = hourlyDay?.temperatura?
            .first(where: { Int($0.periodo ?? "") == nowHour })?.value.flatMap { Double($0) }

        let hourPoints = Self.hourPoints(from: hourly)

        let isoFmt = ISO8601DateFormatter(); isoFmt.formatOptions = [.withFullDate]
        let dayPoints: [AemetDayPoint] = (daily?.prediccion?.dia ?? []).prefix(6).compactMap { day in
            guard let date = isoFmt.date(from: String((day.fecha ?? "").prefix(10))) else { return nil }
            return AemetDayPoint(
                date: date,
                tempMin: day.temperatura?.minima.map { Int($0.rounded()) },
                tempMax: day.temperatura?.maxima.map { Int($0.rounded()) },
                skyCode: dayPickPeriod(day.estadoCielo)?.value,
                prob: dayMaxValue(day.probPrecipitacion)?.value.flatMap { Int($0) }
            )
        }

        return AemetSnapshot(
            municipio: municipio,
            tempMin: today?.temperatura?.minima.map { Int($0.rounded()) },
            tempMax: today?.temperatura?.maxima.map { Int($0.rounded()) },
            currentTemp: currentTemp.map { Int($0.rounded()) },
            skyDescription: skyDesc,
            skyCode: skyCode,
            date: Date(),
            hourly: hourPoints.isEmpty ? nil : hourPoints,
            daily: dayPoints.isEmpty ? nil : dayPoints,
            alert: alert
        )
    }

    /// Next ~8 hours (within 48h) from an hourly root, for the widget strip.
    private static func hourPoints(from hourly: AemetHourlyRoot?) -> [AemetHourPoint] {
        let days = hourly?.prediccion?.dia ?? []
        let now = Date(); let cal = Calendar.current
        let isoFmt = ISO8601DateFormatter(); isoFmt.formatOptions = [.withFullDate]
        let nowFloor = cal.date(bySettingHour: cal.component(.hour, from: now), minute: 0, second: 0, of: now)!
        let cutoff = now.addingTimeInterval(48 * 3600)
        var result: [AemetHourPoint] = []
        for day in days {
            let dayStr = String((day.fecha ?? "").prefix(10))
            guard let dayDate = isoFmt.date(from: dayStr) else { continue }
            for tEntry in (day.temperatura ?? []) {
                guard let hour = Int(tEntry.periodo ?? ""),
                      let temp = Double(tEntry.value ?? ""),
                      let entryDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: dayDate),
                      entryDate >= nowFloor && entryDate <= cutoff else { continue }
                let sky = day.estadoCielo?.first(where: { Int($0.periodo ?? "") == hour })?.value
                let probStr = day.probPrecipitacion?.first(where: { p in
                    guard let per = p.periodo, per.count == 4 else { return false }
                    let s = Int(per.prefix(2)) ?? 0; let e = Int(per.suffix(2)) ?? 0
                    return hour >= s && hour < e
                })?.value
                result.append(AemetHourPoint(hour: hour, temp: Int(temp.rounded()), skyCode: sky,
                                             prob: probStr.flatMap { Int($0) },
                                             isToday: cal.isDateInToday(dayDate)))
            }
        }
        return Array(result.prefix(8))
    }

    /// Static twins of the instance `pickPeriod` / `maxOfDay` helpers.
    private static func dayPickPeriod(_ arr: [AemetPeriodValue]?) -> AemetPeriodValue? {
        guard let arr else { return nil }
        for p in ["00-24", "12-24", "06-24"] {
            if let m = arr.first(where: { $0.periodo == p && ($0.value ?? "").isEmpty == false }) { return m }
        }
        return arr.first(where: { ($0.value ?? "").isEmpty == false }) ?? arr.first
    }

    private static func dayMaxValue(_ arr: [AemetPeriodValue]?) -> AemetPeriodValue? {
        arr?.max(by: { (Double($0.value ?? "") ?? 0) < (Double($1.value ?? "") ?? 0) })
    }

    private func geolocate() {
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        guard let loc = mgr.location else { return }
        let coord = loc.coordinate
        let nearest = store.locations.min(by: { a, b in
            let da = pow(a.lat - coord.latitude, 2) + pow(a.lon - coord.longitude, 2)
            let db = pow(b.lat - coord.latitude, 2) + pow(b.lon - coord.longitude, 2)
            return da < db
        })
        if let n = nearest {
            store.select(n.code)
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
