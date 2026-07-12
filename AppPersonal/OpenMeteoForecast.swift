import Foundation

// Open-Meteo forecast fallback (no API key). When AEMET is not configured, we fetch the
// public Open-Meteo forecast and adapt it into the very same AEMET model structs the
// AemetView (and the widget snapshot builder) already consume — so no view needs to know
// which provider is behind the data. Docs: https://open-meteo.com/en/docs
//
// Only the fields the UI reads are filled; everything else is left nil.

extension OpenMeteoService {

    /// Forecast bundle shaped like the AEMET roots the views expect.
    struct Forecast {
        let daily: AemetDailyRoot
        let hourly: AemetHourlyRoot
        let obs: [AemetObservationRecord]   // one synthetic "current conditions" record
    }

    // MARK: - Fetch

    func fetchForecast(lat: Double, lon: Double) async -> Forecast? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_gusts_10m,precipitation,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,precipitation_probability_max,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONDecoder().decode(ForecastRoot.self, from: data) else { return nil }
        return Self.adapt(root)
    }

    // MARK: - Raw Open-Meteo shapes

    private struct ForecastRoot: Decodable {
        let current: Current?
        let hourly: Hourly?
        let daily: Daily?

        struct Current: Decodable {
            let temperature_2m: Double?
            let relative_humidity_2m: Double?
            let weather_code: Int?
            let wind_speed_10m: Double?
            let wind_gusts_10m: Double?
            let precipitation: Double?
            let is_day: Int?
        }
        struct Hourly: Decodable {
            let time: [String]?
            let temperature_2m: [Double?]?
            let weather_code: [Int?]?
            let precipitation_probability: [Int?]?
            let is_day: [Int?]?
        }
        struct Daily: Decodable {
            let time: [String]?
            let weather_code: [Int?]?
            let temperature_2m_max: [Double?]?
            let temperature_2m_min: [Double?]?
            let apparent_temperature_max: [Double?]?
            let apparent_temperature_min: [Double?]?
            let precipitation_probability_max: [Int?]?
            let uv_index_max: [Double?]?
            let wind_speed_10m_max: [Double?]?
            let wind_gusts_10m_max: [Double?]?
            let wind_direction_10m_dominant: [Double?]?
        }
    }

    // MARK: - Adapt Open-Meteo → AEMET structs

    private static func adapt(_ r: ForecastRoot) -> Forecast {
        let origen = AemetOrigen(productor: "Open-Meteo (open-meteo.com)", web: "https://open-meteo.com",
                                 enlace: nil, notaLegal: nil, copyright: nil, licencia: "CC BY 4.0")

        // --- Hourly: group each hour under its day ---
        var hourlyDays: [AemetHourlyDay] = []
        if let h = r.hourly, let times = h.time {
            var byDay: [String: (t: [AemetPeriodValue], sky: [AemetPeriodValue], prob: [AemetPeriodValue])] = [:]
            var order: [String] = []
            for (i, iso) in times.enumerated() {
                let day = String(iso.prefix(10))
                let hour = Int(iso.dropFirst(11).prefix(2)) ?? 0     // "...T14:00" → 14
                if byDay[day] == nil { byDay[day] = ([], [], []); order.append(day) }
                let hh = String(format: "%02d", hour)
                if let t = h.temperature_2m?[safe: i] ?? nil {
                    byDay[day]!.t.append(AemetPeriodValue(periodo: hh, value: String(Int(t.rounded()))))
                }
                let isDay = (h.is_day?[safe: i] ?? nil) != 0
                if let wc = h.weather_code?[safe: i] ?? nil {
                    byDay[day]!.sky.append(AemetPeriodValue(periodo: hh, value: skyCode(wc, day: isDay),
                                                            descripcion: skyText(wc)))
                }
                if let p = h.precipitation_probability?[safe: i] ?? nil {
                    let range = String(format: "%02d%02d", hour, hour + 1)  // matches the hour-range lookup
                    byDay[day]!.prob.append(AemetPeriodValue(periodo: range, value: String(p)))
                }
            }
            hourlyDays = order.map { day in
                let e = byDay[day]!
                return AemetHourlyDay(fecha: day, temperatura: e.t, estadoCielo: e.sky, probPrecipitacion: e.prob)
            }
        }
        let hourly = AemetHourlyRoot(nombre: nil, provincia: nil,
                                     elaborado: isoNow(), prediccion: AemetHourlyPred(dia: hourlyDays),
                                     origen: origen)

        // --- Daily ---
        var dailyDays: [AemetDailyDay] = []
        if let d = r.daily, let times = d.time {
            for (i, day) in times.enumerated() {
                let sky = d.weather_code?[safe: i].flatMap { $0 }
                let windMs = d.wind_speed_10m_max?[safe: i].flatMap { $0 }
                let dir = d.wind_direction_10m_dominant?[safe: i].flatMap { $0 }
                dailyDays.append(AemetDailyDay(
                    fecha: day,
                    temperatura: AemetMinMax(maxima: d.temperature_2m_max?[safe: i].flatMap { $0 },
                                             minima: d.temperature_2m_min?[safe: i].flatMap { $0 }),
                    sensTermica: AemetMinMax(maxima: d.apparent_temperature_max?[safe: i].flatMap { $0 },
                                             minima: d.apparent_temperature_min?[safe: i].flatMap { $0 }),
                    humedadRelativa: nil,
                    estadoCielo: sky.map { [AemetPeriodValue(periodo: "00-24", value: skyCode($0, day: true),
                                                             descripcion: skyText($0))] },
                    probPrecipitacion: (d.precipitation_probability_max?[safe: i].flatMap { $0 })
                        .map { [AemetPeriodValue(periodo: "00-24", value: String($0))] },
                    rachaMax: (d.wind_gusts_10m_max?[safe: i].flatMap { $0 })
                        .map { [AemetPeriodValue(periodo: "00-24", value: String(Int(($0 * 3.6).rounded())))] },
                    viento: windMs.map { [AemetWindEntry(periodo: "00-24",
                                                         velocidad: String(Int(($0 * 3.6).rounded())),
                                                         direccion: dir.map(compass) ?? "")] },
                    cotaNieveProv: nil,
                    uvMax: (d.uv_index_max?[safe: i].flatMap { $0 }).map { Int($0.rounded()) }))
            }
        }
        let daily = AemetDailyRoot(nombre: nil, provincia: nil,
                                   elaborado: isoNow(), prediccion: AemetDailyPred(dia: dailyDays),
                                   origen: origen)

        // --- Current conditions → one synthetic observation record ---
        var obs: [AemetObservationRecord] = []
        if let c = r.current {
            obs = [AemetObservationRecord(fint: obsNow(), ta: c.temperature_2m, hr: c.relative_humidity_2m,
                                          vv: c.wind_speed_10m, vmax: c.wind_gusts_10m, prec: c.precipitation)]
        }

        return Forecast(daily: daily, hourly: hourly, obs: obs)
    }

    // MARK: - WMO code mapping

    /// WMO weather code → AEMET-style sky code string that `WeatherIconView` understands
    /// (numeric base + optional "n" night suffix).
    private static func skyCode(_ wmo: Int, day: Bool) -> String {
        let base: Int
        switch wmo {
        case 0:                     base = 11   // clear
        case 1:                     base = 12   // mainly clear
        case 2:                     base = 13   // partly cloudy
        case 3:                     base = 15   // overcast
        case 45, 48:                base = 81   // fog
        case 51, 53, 55, 56, 57:    base = 43   // drizzle
        case 61, 63, 65, 66, 67:    base = 24   // rain
        case 80, 81, 82:            base = 44   // rain showers
        case 71, 73, 75, 77, 85, 86: base = 34  // snow
        case 95:                    base = 52   // thunderstorm
        case 96, 99:                base = 62   // thunderstorm with hail
        default:                    base = 15
        }
        return day ? "\(base)" : "\(base)n"
    }

    private static func skyText(_ wmo: Int) -> String {
        switch wmo {
        case 0:                     return "Despejado"
        case 1:                     return "Poco nuboso"
        case 2:                     return "Parcialmente nuboso"
        case 3:                     return "Cubierto"
        case 45, 48:                return "Niebla"
        case 51, 53, 55, 56, 57:    return "Llovizna"
        case 61, 63, 65, 66, 67:    return "Lluvia"
        case 80, 81, 82:            return "Chubascos"
        case 71, 73, 75, 77:        return "Nieve"
        case 85, 86:                return "Chubascos de nieve"
        case 95, 96, 99:            return "Tormenta"
        default:                    return "—"
        }
    }

    private nonisolated static func compass(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        return dirs[Int((deg / 45).rounded()) % 8]
    }

    /// AEMET `elaborado` uses a plain ISO-8601 instant.
    private static func isoNow() -> String { ISO8601DateFormatter().string(from: Date()) }

    /// AEMET observation `fint` is a timezone-less UTC stamp; `freshObsTemp` parses it that
    /// way and only trusts readings ≤2 h old, so stamp "now" in UTC.
    private static func obsNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: Date())
    }
}

private extension Array {
    /// Bounds-safe subscript — Open-Meteo returns parallel arrays that should match, but
    /// guard against a short one rather than crashing.
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
