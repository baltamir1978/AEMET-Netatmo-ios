import Foundation

// Open-Meteo client (no API key). Complements AEMET with the data it doesn't
// provide: air quality, pollen (CAMS Europe) and UV index.
// https://open-meteo.com/en/docs/air-quality-api  +  forecast API for UV.

struct OpenMeteoData {
    struct Pollen: Identifiable {
        var id: String { name }
        let name: String      // localized label
        let value: Double     // grains/m³
    }
    let aqi: Int?             // European AQI
    let pm25: Double?
    let pm10: Double?
    let uvIndex: Double?      // current
    let uvMax: Double?        // today's max
    let pollen: [Pollen]      // only species with a reading

    var hasContent: Bool {
        aqi != nil || uvIndex != nil || uvMax != nil || !pollen.isEmpty
    }
}

struct OpenMeteoService {
    static let shared = OpenMeteoService()

    private static let pollenLabels: [(key: String, label: String)] = [
        ("alder_pollen",   "Aliso"),
        ("birch_pollen",   "Abedul"),
        ("grass_pollen",   "Gramíneas"),
        ("mugwort_pollen", "Artemisa"),
        ("olive_pollen",   "Olivo"),
        ("ragweed_pollen", "Ambrosía"),
    ]

    func fetch(lat: Double, lon: Double) async -> OpenMeteoData? {
        async let air = fetchAir(lat: lat, lon: lon)
        async let uv  = fetchUV(lat: lat, lon: lon)
        let (a, u) = await (air, uv)
        let data = OpenMeteoData(
            aqi: a?.european_aqi.map { Int($0.rounded()) },
            pm25: a?.pm2_5, pm10: a?.pm10,
            uvIndex: u?.current, uvMax: u?.max,
            pollen: a?.pollen ?? []
        )
        return data.hasContent ? data : nil
    }

    // MARK: - Air quality + pollen

    private struct AirResult {
        let european_aqi: Double?
        let pm2_5: Double?
        let pm10: Double?
        let pollen: [OpenMeteoData.Pollen]
    }

    private func fetchAir(lat: Double, lon: Double) async -> AirResult? {
        let fields = ["european_aqi", "pm2_5", "pm10"] + Self.pollenLabels.map { $0.key }
        var comps = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: fields.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONDecoder().decode(AirRoot.self, from: data) else { return nil }
        let cur = root.current
        let pollen = Self.pollenLabels.compactMap { entry -> OpenMeteoData.Pollen? in
            guard let v = cur?.values[entry.key], v > 0 else { return nil }
            return OpenMeteoData.Pollen(name: entry.label, value: v)
        }
        return AirResult(european_aqi: cur?.values["european_aqi"],
                         pm2_5: cur?.values["pm2_5"],
                         pm10: cur?.values["pm10"],
                         pollen: pollen)
    }

    // Decodes the `current` object with arbitrary numeric keys.
    private struct AirRoot: Decodable {
        let current: Current?
        struct Current: Decodable {
            var values: [String: Double] = [:]
            private struct CodingKeys: CodingKey {
                var stringValue: String; var intValue: Int? { nil }
                init?(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { return nil }
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                for key in c.allKeys {
                    if let v = try? c.decode(Double.self, forKey: key) { values[key.stringValue] = v }
                }
            }
        }
    }

    // MARK: - UV (forecast API)

    private struct UVResult { let current: Double?; let max: Double? }

    private func fetchUV(lat: Double, lon: Double) async -> UVResult? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "uv_index"),
            URLQueryItem(name: "daily", value: "uv_index_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONDecoder().decode(UVRoot.self, from: data) else { return nil }
        return UVResult(current: root.current?.uv_index, max: root.daily?.uv_index_max?.first ?? nil)
    }

    private struct UVRoot: Decodable {
        let current: Cur?
        let daily: Daily?
        struct Cur: Decodable { let uv_index: Double? }
        struct Daily: Decodable { let uv_index_max: [Double?]? }
    }

    // MARK: - Helpers (shared by the view)

    /// European AQI band → (label, 0–5 severity index for coloring).
    static func aqiBand(_ aqi: Int) -> (label: String, severity: Int) {
        switch aqi {
        case ..<20:  return ("Buena", 0)
        case ..<40:  return ("Razonable", 1)
        case ..<60:  return ("Moderada", 2)
        case ..<80:  return ("Pobre", 3)
        case ..<100: return ("Muy pobre", 4)
        default:     return ("Extrem. pobre", 5)
        }
    }

    /// Coarse pollen level by grains/m³ (indicative; thresholds vary by species).
    static func pollenLevel(_ v: Double) -> (label: String, severity: Int) {
        switch v {
        case ..<10:  return ("Bajo", 0)
        case ..<50:  return ("Moderado", 2)
        case ..<150: return ("Alto", 3)
        default:     return ("Muy alto", 5)
        }
    }
}
