import SwiftUI
import Charts

// MARK: - Local chart data model

struct ChartData {
    let labels: [String]
    let values: [Double]
    let isData: [Bool]?
    let min: Double?
    let max: Double?
    let minLabel: String?
    let maxLabel: String?
    let total: Double?
    let rainyDays: Int?
}

/// Which Netatmo module a chart reads from. Pressure is measured by the base station,
/// so it is always an interior chart even though Actual shows it among the exterior tiles.
enum NetatmoChartSource: Hashable {
    case exterior, interior

    var title: String { self == .exterior ? "Exterior" : "Interior" }

    /// (measure type, menu label) — the labels double as the detail screen's title.
    var types: [(String, String)] {
        switch self {
        case .exterior:
            return [("Temperature", "Temperatura ext."),
                    ("Humidity",    "Humedad ext."),
                    ("Rain",        "Lluvia")]
        case .interior:
            return [("Temperature", "Temperatura"),
                    ("CO2",         "CO₂"),
                    ("Humidity",    "Humedad"),
                    ("Noise",       "Ruido"),
                    ("Pressure",    "Presión")]
        }
    }
}

// MARK: - View

struct GraficasView: View {
    @State private var period = "semana"
    @State private var exteriorType = "Temperature"
    @State private var interiorType = "Temperature"
    @State private var exteriorChart: ChartData?
    @State private var interiorChart: ChartData?
    @State private var loadingExt = false
    @State private var loadingInt = false
    @State private var exteriorError: String?
    @State private var interiorError: String?
    @State private var configError = false
    @Environment(\.verticalSizeClass) private var vSize

    /// Landscape on iPhone reports a compact height.
    private var isLandscape: Bool { vSize == .compact }
    private var chartHeight: CGFloat { isLandscape ? 240 : 200 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: isLandscape ? 12 : 20) {
                    if configError {
                        Label("Configura Netatmo en Ajustes", systemImage: "gearshape")
                            .font(.caption).foregroundStyle(.secondary).padding()
                    }
                    ChartPeriodSelector(period: $period, compact: isLandscape) { loadBoth() }
                    if isLandscape {
                        HStack(alignment: .top, spacing: 16) {
                            exteriorCard.frame(maxWidth: .infinity)
                            interiorCard.frame(maxWidth: .infinity)
                        }
                    } else {
                        exteriorCard
                        interiorCard
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, isLandscape ? 8 : 16)
            }
            .navigationTitle("Gráficas")
            // The bottom tab already says "Gráficas" — hide the bulky title bar in landscape.
            .navigationBarTitleDisplayMode(isLandscape ? .inline : .large)
            .toolbar(isLandscape ? .hidden : .automatic, for: .navigationBar)
            .task { loadBoth() }
        }
    }

    private var exteriorCard: some View {
        ChartCard(
            title: NetatmoChartSource.exterior.title,
            typeOptions: NetatmoChartSource.exterior.types,
            selectedType: $exteriorType,
            chartData: exteriorChart,
            isLoading: loadingExt,
            errorText: exteriorError,
            chartHeight: chartHeight,
            onTypeChange: { loadExterior() }
        )
    }

    private var interiorCard: some View {
        ChartCard(
            title: NetatmoChartSource.interior.title,
            typeOptions: NetatmoChartSource.interior.types,
            selectedType: $interiorType,
            chartData: interiorChart,
            isLoading: loadingInt,
            errorText: interiorError,
            chartHeight: chartHeight,
            onTypeChange: { loadInterior() }
        )
    }

    // MARK: - Loading

    private func loadBoth() {
        let cfg = AppConfiguration.shared
        configError = !cfg.isNetatmoConfigured
        guard !configError else { return }
        loadExterior()
        loadInterior()
    }

    private func loadExterior() {
        loadingExt = true
        exteriorError = nil
        Task {
            let r = await NetatmoChartLoader.load(.exterior, type: exteriorType, period: period)
            exteriorChart = r.chart
            exteriorError = r.error
            loadingExt = false
        }
    }

    private func loadInterior() {
        loadingInt = true
        interiorError = nil
        Task {
            let r = await NetatmoChartLoader.load(.interior, type: interiorType, period: period)
            interiorChart = r.chart
            interiorError = r.error
            loadingInt = false
        }
    }
}

// MARK: - Single-metric chart (pushed from a tile in Actual)

struct MetricChartView: View {
    let source: NetatmoChartSource
    let type: String

    @State private var period = "semana"
    @State private var chart: ChartData?
    @State private var isLoading = false
    @State private var errorText: String?
    @Environment(\.verticalSizeClass) private var vSize

    private var isLandscape: Bool { vSize == .compact }

    private var title: String {
        source.types.first { $0.0 == type }?.1 ?? source.title
    }

    var body: some View {
        ScrollView {
            VStack(spacing: isLandscape ? 12 : 20) {
                ChartPeriodSelector(period: $period, compact: isLandscape) { load() }
                ChartCard(
                    title: source.title,
                    // Only this metric: switching type here would contradict the tile tapped.
                    typeOptions: [],
                    selectedType: .constant(type),
                    chartData: chart,
                    isLoading: isLoading,
                    errorText: errorText,
                    chartHeight: isLandscape ? 240 : 280,
                    onTypeChange: {}
                )
            }
            .padding(.horizontal)
            .padding(.vertical, isLandscape ? 8 : 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task {
            let r = await NetatmoChartLoader.load(source, type: type, period: period)
            chart = r.chart
            errorText = r.error
            isLoading = false
        }
    }
}

// MARK: - Period selector

struct ChartPeriodSelector: View {
    @Binding var period: String
    /// Landscape: a full-width segmented control to reclaim vertical space.
    let compact: Bool
    let onChange: () -> Void

    private let periods = [("semana", "Semana"), ("mes", "Mes"), ("meses3", "3 Meses"), ("anio", "Año")]

    var body: some View {
        if compact {
            Picker("Periodo", selection: $period) {
                ForEach(periods, id: \.0) { (key, label) in
                    Text(LocalizedStringKey(label)).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: period) { _, _ in onChange() }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Periodo")
                    .font(.caption).fontWeight(.bold).textCase(.uppercase)
                    .foregroundStyle(.secondary).tracking(1.5)
                HStack(spacing: 6) {
                    ForEach(periods, id: \.0) { (key, label) in
                        Button(LocalizedStringKey(label)) {
                            period = key
                            onChange()
                        }
                        .font(.subheadline).fontWeight(.medium)
                        // Large type: shrink rather than split "Semana" across two lines.
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(period == key ? AppTheme.green : Color(.systemBackground))
                        .foregroundStyle(period == key ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4)))
                        .accessibilityAddTraits(period == key ? .isSelected : [])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Loading

/// `getmeasure` for one chart, shared by Gráficas and the per-tile charts in Actual.
enum NetatmoChartLoader {
    static func load(_ source: NetatmoChartSource, type: String,
                     period: String) async -> (chart: ChartData?, error: String?) {
        let cfg = AppConfiguration.shared
        let deviceId = cfg.deviceId
        guard !deviceId.isEmpty else { return (nil, nil) }

        let isRain = source == .exterior && type == "Rain"
        let moduleId: String
        switch source {
        case .interior:
            moduleId = deviceId
        case .exterior:
            let configured = isRain ? cfg.moduleRain : cfg.moduleExterior
            // Asking the base station for `sum_rain` returns an empty body forever, which used
            // to look exactly like "no ha llovido". Say what is actually wrong instead.
            if isRain && configured.isEmpty {
                return (nil, String(localized: "No hay pluviómetro configurado."))
            }
            moduleId = configured.isEmpty ? deviceId : configured
        }

        let (scale, days) = scaleAndDays(period)
        // `getmeasure` only accepts `sum_rain` for the rain gauge; `Sum_rain_1/24`
        // are dashboard_data fields and return an empty body here.
        let measureType = isRain ? "sum_rain" : type
        let dateBegin = dateBeginUnix(days: days)

        do {
            let resp = isRain
                ? try await rainMeasure(deviceId: deviceId, moduleId: moduleId,
                                        scale: scale, dateBegin: dateBegin)
                : try await NetatmoService.shared.getMeasure(
                    deviceId: deviceId, moduleId: moduleId, scale: scale,
                    types: [measureType], dateBegin: dateBegin)
            if let apiError = resp.error { return (nil, describe(apiError)) }
            // An empty body is not "no rain": dry intervals still come back as zeros.
            guard let chart = buildChartData(from: resp, scale: scale, isRain: isRain) else {
                return (nil, String(localized: "El módulo no devolvió medidas."))
            }
            return (chart, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// Netatmo answers "Service temporarily unavailable" to anything it can't serve, which
    /// includes a `module_id` that no longer belongs to the station — indistinguishable from
    /// a real outage. So: ask in real time first (the only way to see the slot in progress),
    /// then plainly, then with the gauge re-detected from the station itself.
    private static func rainMeasure(deviceId: String, moduleId: String,
                                    scale: String, dateBegin: Int) async throws -> GetMeasureResponse {
        func ask(_ module: String, realTime: Bool) async throws -> GetMeasureResponse {
            try await NetatmoService.shared.getMeasure(
                deviceId: deviceId, moduleId: module, scale: scale,
                types: ["sum_rain"], dateBegin: dateBegin, realTime: realTime)
        }
        func usable(_ r: GetMeasureResponse) -> Bool { r.error == nil && !(r.body?.isEmpty ?? true) }

        let realTimeTry = try await ask(moduleId, realTime: true)
        if usable(realTimeTry) { return realTimeTry }

        let plainTry = try await ask(moduleId, realTime: false)
        if usable(plainTry) { return plainTry }

        // Last resort: the stored id may be stale (a replaced gauge keeps its own id).
        if let detected = await detectRainModule(deviceId: deviceId), detected != moduleId {
            let detectedTry = try await ask(detected, realTime: true)
            if usable(detectedTry) {
                AppConfiguration.shared.moduleRain = detected
                return detectedTry
            }
        }
        return realTimeTry
    }

    /// The `NAModule3` currently attached to the station, straight from `getstationsdata`.
    private static func detectRainModule(deviceId: String) async -> String? {
        guard let resp = try? await NetatmoService.shared.getStationsData() else { return nil }
        let devices = resp.body?.devices ?? []
        let main = devices.first { $0.id == deviceId } ?? devices.first
        return main?.modules?.first { $0.type == "NAModule3" }?.id
    }

    /// Netatmo's own wording plus its code — "Maximum usage reached" (rate limit) and a
    /// dead module both arrive as generic-sounding text otherwise.
    private static func describe(_ error: NetatmoAPIError) -> String {
        let message = error.message ?? String(localized: "Error de Netatmo")
        return error.code.map { "\(message) (\($0))" } ?? message
    }

    private static func scaleAndDays(_ period: String) -> (String, Int) {
        switch period {
        case "mes":    return ("1day",   30)
        case "meses3": return ("1day",   90)
        case "anio":   return ("1week", 365)
        default:       return ("3hours",  7)
        }
    }

    private static func dateBeginUnix(days: Int) -> Int {
        Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
    }

    private static func buildChartData(from resp: GetMeasureResponse, scale: String, isRain: Bool) -> ChartData? {
        guard let body = resp.body, !body.isEmpty else { return nil }

        let sorted: [(Int, Double)] = body.compactMap { k, v in
            guard let ts = Int(k) else { return nil }
            let val = v.first.flatMap { $0 }
            guard let val else { return nil }
            return (ts, val)
        }.sorted { $0.0 < $1.0 }

        guard !sorted.isEmpty else { return nil }

        let values = sorted.map { $0.1 }

        let labelFmt = DateFormatter()
        labelFmt.locale = Locale(identifier: "es_ES")
        labelFmt.dateFormat = scale == "3hours" ? "d/M HH'h'" : "d MMM"
        let labels = sorted.map { labelFmt.string(from: Date(timeIntervalSince1970: TimeInterval($0.0))) }

        if isRain {
            let total = values.reduce(0, +)
            let maxVal = values.max()
            let maxIdx = maxVal.flatMap { mv in values.firstIndex(where: { $0 == mv }) }
            let rainyDays = values.filter { $0 > 0 }.count
            return ChartData(
                labels: labels, values: values, isData: values.map { $0 > 0 },
                min: nil, max: maxVal,
                minLabel: nil, maxLabel: maxIdx.map { labels[$0] },
                total: total, rainyDays: rainyDays
            )
        } else {
            let minVal = values.min()
            let maxVal = values.max()
            let minIdx = minVal.flatMap { mv in values.firstIndex(where: { $0 == mv }) }
            let maxIdx = maxVal.flatMap { mv in values.firstIndex(where: { $0 == mv }) }
            return ChartData(
                labels: labels, values: values, isData: nil,
                min: minVal, max: maxVal,
                minLabel: minIdx.map { labels[$0] },
                maxLabel: maxIdx.map { labels[$0] },
                total: nil, rainyDays: nil
            )
        }
    }
}


// MARK: - Chart Card

struct ChartCard: View {
    let title: String
    let typeOptions: [(String, String)]
    @Binding var selectedType: String
    let chartData: ChartData?
    let isLoading: Bool
    var errorText: String? = nil
    var chartHeight: CGFloat = 200
    let onTypeChange: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var typeColor: Color {
        switch selectedType {
        case "Temperature": return .orange
        case "Humidity":    return .blue
        case "Pressure":    return AppTheme.green
        case "CO2":         return .purple
        case "Noise":       return .gray
        case "Rain":        return .indigo
        default:            return AppTheme.green
        }
    }

    /// Whether the selected metric is grammatically feminine (la temperatura/humedad/presión)
    /// so the stat labels read "Máxima/Mínima" instead of "Máximo/Mínimo".
    private var statFeminine: Bool {
        ["Temperature", "Humidity", "Pressure", "Rain"].contains(selectedType)
    }

    private var typeUnit: String {
        switch selectedType {
        case "Temperature": return "°C"
        case "Humidity":    return "%"
        case "Pressure":    return "hPa"
        case "CO2":         return "ppm"
        case "Noise":       return "dB"
        case "Rain":        return "L/m²"
        default:            return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.caption).fontWeight(.bold).textCase(.uppercase)
                    .foregroundStyle(.secondary).tracking(1)
                Spacer()
                // A single-metric card (opened from a tile) has nothing to choose from.
                if !typeOptions.isEmpty {
                    Picker("", selection: $selectedType) {
                        ForEach(typeOptions, id: \.0) { (key, label) in
                            Text(LocalizedStringKey(label)).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedType) { _, _ in onTypeChange() }
                }
            }
            // Same height with or without the menu, so the header doesn't shrink.
            .frame(minHeight: 32)
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            if isLoading {
                ProgressView().frame(height: chartHeight)
            } else if let data = chartData {
                chartBody(data: data)
                Divider()
                statsRow(data: data)
            } else {
                VStack(spacing: 6) {
                    Text("Sin datos").foregroundStyle(.secondary)
                    if let errorText {
                        Text(errorText)
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(height: chartHeight)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private func chartBody(data: ChartData) -> some View {
        // Big date labels need room, or they print on top of each other.
        let tickStep = max(1, data.labels.count / (typeSize.isAccessibilitySize ? 3 : 8))
        let entries = Array(data.values.enumerated())

        if selectedType == "Rain" {
            Chart {
                ForEach(entries, id: \.offset) { i, val in
                    let active = data.isData?[i] == true
                    BarMark(x: .value("Fecha", i), y: .value("mm", val))
                        .foregroundStyle(active && val > 0 ? typeColor.opacity(0.8) : Color(.systemGray5))
                }
            }
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 0, to: data.labels.count, by: tickStep))) { idx in
                    AxisValueLabel {
                        if let i = idx.as(Int.self), i < data.labels.count {
                            Text(data.labels[i]).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: chartHeight)
            .padding(.horizontal, 16).padding(.vertical, 12)
        } else {
            Chart {
                ForEach(entries, id: \.offset) { i, val in
                    LineMark(x: .value("Fecha", i), y: .value(typeUnit, val))
                        .foregroundStyle(typeColor)
                    AreaMark(x: .value("Fecha", i), y: .value(typeUnit, val))
                        .foregroundStyle(typeColor.opacity(0.1))
                }
            }
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 0, to: data.labels.count, by: tickStep))) { idx in
                    AxisValueLabel {
                        if let i = idx.as(Int.self), i < data.labels.count {
                            Text(data.labels[i]).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: chartHeight)
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func statsRow(data: ChartData) -> some View {
        if selectedType == "Rain" {
            HStack(spacing: 0) {
                statItem(label: "Total",
                         value: data.total.map { "\(String(format: "%.1f", $0)) L/m²" } ?? "—",
                         date: nil)
                Divider()
                statItem(label: "Máx. período",
                         value: data.max.map { "\(String(format: "%.1f", $0)) L/m²" } ?? "—",
                         date: data.maxLabel)
                Divider()
                statItem(label: "Días lluvia",
                         value: data.rainyDays.map { "\($0)" } ?? "—",
                         date: nil)
            }
            .frame(minHeight: 60)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 0) {
                statItem(label: statFeminine ? "Mínima" : "Mínimo",
                         value: data.min.map { "\(String(format: "%.1f", $0)) \(typeUnit)" } ?? "—",
                         date: data.minLabel)
                Divider()
                let avg = data.values.isEmpty ? "—"
                    : String(format: "%.1f \(typeUnit)", data.values.reduce(0, +) / Double(data.values.count))
                statItem(label: "Promedio", value: avg, date: nil)
                Divider()
                statItem(label: statFeminine ? "Máxima" : "Máximo",
                         value: data.max.map { "\(String(format: "%.1f", $0)) \(typeUnit)" } ?? "—",
                         date: data.maxLabel)
            }
            .frame(minHeight: 60)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statItem(label: String, value: String, date: String?) -> some View {
        VStack(spacing: 2) {
            Text(LocalizedStringKey(label))
                .font(.caption2).fontWeight(.semibold).textCase(.uppercase).foregroundStyle(.secondary)
            Text(value).font(.subheadline).fontWeight(.bold)
            if let d = date { Text(d).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
