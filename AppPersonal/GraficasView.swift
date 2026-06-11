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

// MARK: - View

struct GraficasView: View {
    @State private var period = "semana"
    @State private var exteriorType = "Temperature"
    @State private var interiorType = "Temperature"
    @State private var exteriorChart: ChartData?
    @State private var interiorChart: ChartData?
    @State private var loadingExt = false
    @State private var loadingInt = false
    @State private var configError = false
    @Environment(\.verticalSizeClass) private var vSize

    /// Landscape on iPhone reports a compact height.
    private var isLandscape: Bool { vSize == .compact }
    private var chartHeight: CGFloat { isLandscape ? 240 : 200 }

    private let periods = [("semana", "Semana"), ("mes", "Mes"), ("meses3", "3 Meses"), ("anio", "Año")]

    private let exteriorTypes = [
        ("Temperature", "exterior", "Temperatura ext."),
        ("Humidity",    "exterior", "Humedad ext."),
        ("Rain",        "lluvia",   "Lluvia"),
    ]

    private let interiorTypes = [
        ("Temperature", "interior", "Temperatura"),
        ("CO2",         "interior", "CO₂"),
        ("Humidity",    "interior", "Humedad"),
        ("Noise",       "interior", "Ruido"),
        ("Pressure",    "interior", "Presión"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: isLandscape ? 12 : 20) {
                    if configError {
                        Label("Configura Netatmo en Ajustes", systemImage: "gearshape")
                            .font(.caption).foregroundStyle(.secondary).padding()
                    }
                    periodSelector
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
            title: "Exterior",
            typeOptions: exteriorTypes.map { ($0.0, $0.2) },
            selectedType: $exteriorType,
            chartData: exteriorChart,
            isLoading: loadingExt,
            chartHeight: chartHeight,
            onTypeChange: { loadExterior() }
        )
    }

    private var interiorCard: some View {
        ChartCard(
            title: "Interior",
            typeOptions: interiorTypes.map { ($0.0, $0.2) },
            selectedType: $interiorType,
            chartData: interiorChart,
            isLoading: loadingInt,
            chartHeight: chartHeight,
            onTypeChange: { loadInterior() }
        )
    }

    @ViewBuilder
    private var periodSelector: some View {
        if isLandscape {
            // Compact full-width segmented control to reclaim vertical space.
            Picker("Periodo", selection: $period) {
                ForEach(periods, id: \.0) { (key, label) in
                    Text(label).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: period) { _, _ in loadBoth() }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Periodo")
                    .font(.caption).fontWeight(.bold).textCase(.uppercase)
                    .foregroundStyle(.secondary).tracking(1.5)
                HStack(spacing: 6) {
                    ForEach(periods, id: \.0) { (key, label) in
                        Button(label) {
                            period = key
                            loadBoth()
                        }
                        .font(.subheadline).fontWeight(.medium)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(period == key ? AppTheme.green : Color(.systemBackground))
                        .foregroundStyle(period == key ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        let cfg = AppConfiguration.shared
        let deviceId = cfg.deviceId
        guard !deviceId.isEmpty else { return }

        let isRain = exteriorType == "Rain"
        let moduleId = isRain ? cfg.moduleRain : cfg.moduleExterior
        let (scale, days) = scaleAndDays(period)
        // `getmeasure` only accepts `sum_rain` for the rain gauge; `Sum_rain_1/24`
        // are dashboard_data fields and return an empty body here.
        let measureType = isRain ? "sum_rain" : exteriorType
        let dateBegin = dateBeginUnix(days: days)

        loadingExt = true
        Task {
            do {
                let resp = try await NetatmoService.shared.getMeasure(
                    deviceId: deviceId,
                    moduleId: moduleId.isEmpty ? deviceId : moduleId,
                    scale: scale,
                    types: [measureType],
                    dateBegin: dateBegin
                )
                exteriorChart = buildChartData(from: resp, scale: scale, isRain: isRain)
            } catch {}
            loadingExt = false
        }
    }

    private func loadInterior() {
        let cfg = AppConfiguration.shared
        let deviceId = cfg.deviceId
        guard !deviceId.isEmpty else { return }

        let (scale, days) = scaleAndDays(period)
        let dateBegin = dateBeginUnix(days: days)

        loadingInt = true
        Task {
            do {
                let resp = try await NetatmoService.shared.getMeasure(
                    deviceId: deviceId,
                    moduleId: deviceId,
                    scale: scale,
                    types: [interiorType],
                    dateBegin: dateBegin
                )
                interiorChart = buildChartData(from: resp, scale: scale, isRain: false)
            } catch {}
            loadingInt = false
        }
    }

    // MARK: - Helpers

    private func scaleAndDays(_ period: String) -> (String, Int) {
        switch period {
        case "mes":    return ("1day",   30)
        case "meses3": return ("1day",   90)
        case "anio":   return ("1week", 365)
        default:       return ("3hours",  7)
        }
    }

    private func dateBeginUnix(days: Int) -> Int {
        Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
    }

    private func buildChartData(from resp: GetMeasureResponse, scale: String, isRain: Bool) -> ChartData? {
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
    var chartHeight: CGFloat = 200
    let onTypeChange: () -> Void

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
                Text(title)
                    .font(.caption).fontWeight(.bold).textCase(.uppercase)
                    .foregroundStyle(.secondary).tracking(1)
                Spacer()
                Picker("", selection: $selectedType) {
                    ForEach(typeOptions, id: \.0) { (key, label) in
                        Text(label).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedType) { _, _ in onTypeChange() }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            if isLoading {
                ProgressView().frame(height: chartHeight)
            } else if let data = chartData {
                chartBody(data: data)
                Divider()
                statsRow(data: data)
            } else {
                Text("Sin datos").foregroundStyle(.secondary).frame(height: chartHeight)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private func chartBody(data: ChartData) -> some View {
        let tickStep = max(1, data.labels.count / 8)
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
            .frame(height: 60)
        } else {
            HStack(spacing: 0) {
                statItem(label: "Mínimo",
                         value: data.min.map { "\(String(format: "%.1f", $0)) \(typeUnit)" } ?? "—",
                         date: data.minLabel)
                Divider()
                let avg = data.values.isEmpty ? "—"
                    : String(format: "%.1f \(typeUnit)", data.values.reduce(0, +) / Double(data.values.count))
                statItem(label: "Promedio", value: avg, date: nil)
                Divider()
                statItem(label: "Máximo",
                         value: data.max.map { "\(String(format: "%.1f", $0)) \(typeUnit)" } ?? "—",
                         date: data.maxLabel)
            }
            .frame(height: 60)
        }
    }

    private func statItem(label: String, value: String, date: String?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2).fontWeight(.semibold).textCase(.uppercase).foregroundStyle(.secondary)
            Text(value).font(.subheadline).fontWeight(.bold)
            if let d = date { Text(d).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
