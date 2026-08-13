import Foundation

// MARK: - Station catalog (IHM GetList, sorted alphabetically)

struct TideStation: Identifiable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    /// Only for the two ports that don't run on Spanish time; the rest read their zone
    /// off the coordinates, like every other location in the app.
    var tzOverride: String? = nil

    /// The clock the port's tide times are printed on.
    nonisolated var timeZone: TimeZone {
        let id = tzOverride ?? SavedLocation.timeZoneIdentifier(code: "", lat: lat, lon: lon)
        return TimeZone(identifier: id) ?? TimeZone(identifier: "Europe/Madrid")!
    }
}

// MARK: - Tide (used by TidesService, CosmosView and the tides widget)

struct Tide: Identifiable, Codable {
    var id: String { time + type }
    let time: String
    let height: Double
    let type: String
}

let ihmStations: [TideStation] = [
    TideStation(id: "20", name: "A Coruña",                       lat: 43.37, lon: -8.40),
    TideStation(id: "71", name: "A Guarda",                       lat: 41.90, lon: -8.87),
    TideStation(id: "49", name: "Algeciras",                      lat: 36.13, lon: -5.44),
    TideStation(id: "14", name: "Alúmina Española (San Cibrao)",  lat: 43.70, lon: -7.43),
    TideStation(id: "57", name: "Arinaga (Gran Canaria)",         lat: 27.85, lon: -15.39),
    TideStation(id: "53", name: "Arrecife (Lanzarote)",           lat: 28.96, lon: -13.55),
    TideStation(id: "7",  name: "Avilés (San Juan de Nieva)",     lat: 43.58, lon: -5.95),
    TideStation(id: "32", name: "Ayamonte",                       lat: 37.21, lon: -7.41),
    TideStation(id: "30", name: "Baiona",                         lat: 42.12, lon: -8.85),
    TideStation(id: "47", name: "Barbate",                        lat: 36.19, lon: -5.92),
    TideStation(id: "72", name: "Bermeo",                         lat: 43.42, lon: -2.72),
    TideStation(id: "2",  name: "Bilbao",                         lat: 43.35, lon: -3.04),
    TideStation(id: "37", name: "Bonanza (Sanlúcar de Barrameda)",lat: 36.81, lon: -6.34),
    TideStation(id: "13", name: "Burela",                         lat: 43.66, lon: -7.35),
    TideStation(id: "42", name: "Cádiz",                          lat: 36.53, lon: -6.28),
    TideStation(id: "22", name: "Camariñas",                      lat: 43.13, lon: -9.18),
    TideStation(id: "16", name: "Cariño",                         lat: 43.74, lon: -7.87),
    TideStation(id: "17", name: "Cedeira",                        lat: 43.66, lon: -8.06),
    TideStation(id: "51", name: "Ceuta",                          lat: 35.89, lon: -5.31),
    TideStation(id: "39", name: "Chipiona",                       lat: 36.74, lon: -6.43),
    TideStation(id: "15", name: "Cillero (Ría de Viveiro)",       lat: 43.67, lon: -7.59),
    TideStation(id: "46", name: "Conil",                          lat: 36.28, lon: -6.09),
    TideStation(id: "8",  name: "Cudillero",                      lat: 43.56, lon: -6.15),
    TideStation(id: "41", name: "El Puerto de Santa María",       lat: 36.60, lon: -6.23),
    TideStation(id: "18", name: "Ferrol",                         lat: 43.48, lon: -8.24),
    TideStation(id: "23", name: "Fisterra",                       lat: 42.91, lon: -9.27),
    TideStation(id: "12", name: "Foz",                            lat: 43.57, lon: -7.26),
    TideStation(id: "44", name: "Gallineras",                     lat: 36.44, lon: -6.21),
    TideStation(id: "6",  name: "Gijón",                          lat: 43.55, lon: -5.70),
    TideStation(id: "64", name: "Granadilla (Tenerife)",          lat: 28.07, lon: -16.50),
    TideStation(id: "34", name: "Isla Cristina",                  lat: 37.20, lon: -7.32),
    TideStation(id: "43", name: "La Carraca",                     lat: 36.49, lon: -6.20),
    TideStation(id: "70", name: "Langosteira (A Coruña exterior)",lat: 43.35, lon: -8.50),
    TideStation(id: "31", name: "Lisboa",                         lat: 38.71, lon: -9.14, tzOverride: "Europe/Lisbon"),
    TideStation(id: "4",  name: "Llanes",                         lat: 43.42, lon: -4.75),
    TideStation(id: "63", name: "Los Cristianos (Tenerife)",      lat: 28.05, lon: -16.72),
    TideStation(id: "61", name: "Los Gigantes (Tenerife)",        lat: 28.24, lon: -16.84),
    TideStation(id: "21", name: "Malpica",                        lat: 43.32, lon: -8.81),
    TideStation(id: "33", name: "Marina de Isla Canela",          lat: 37.18, lon: -7.36),
    TideStation(id: "28", name: "Marín (Ría de Pontevedra)",      lat: 42.39, lon: -8.70),
    TideStation(id: "36", name: "Mazagón (Huelva)",               lat: 37.13, lon: -6.83),
    TideStation(id: "55", name: "Morro Jable (Fuerteventura)",    lat: 28.05, lon: -14.35),
    TideStation(id: "9",  name: "Navia",                          lat: 43.54, lon: -6.72),
    TideStation(id: "1",  name: "Pasajes",                        lat: 43.32, lon: -1.92),
    TideStation(id: "58", name: "Pasito Blanco (Gran Canaria)",   lat: 27.75, lon: -15.66),
    TideStation(id: "24", name: "Portosín (Ría de Muros y Noia)", lat: 42.76, lon: -8.94),
    TideStation(id: "62", name: "Puerto de la Cruz (Tenerife)",   lat: 28.42, lon: -16.55),
    TideStation(id: "67", name: "Puerto de la Estaca (El Hierro)",lat: 27.78, lon: -17.89),
    TideStation(id: "56", name: "Puerto de la Luz (Gran Canaria)",lat: 28.14, lon: -15.42),
    TideStation(id: "59", name: "Puerto de las Nieves (Gran Canaria)", lat: 28.10, lon: -15.71),
    TideStation(id: "54", name: "Puerto del Rosario (Fuerteventura)", lat: 28.50, lon: -13.86),
    TideStation(id: "35", name: "Punta Umbría",                   lat: 37.18, lon: -6.96),
    TideStation(id: "11", name: "Ribadeo",                        lat: 43.54, lon: -7.04),
    TideStation(id: "5",  name: "Ribadesella",                    lat: 43.46, lon: -5.06),
    TideStation(id: "40", name: "Rota",                           lat: 36.62, lon: -6.36),
    TideStation(id: "19", name: "Sada Fontán (Ría de Betanzos)",  lat: 43.35, lon: -8.25),
    TideStation(id: "65", name: "San Sebastián de la Gomera",     lat: 28.09, lon: -17.11),
    TideStation(id: "66", name: "Santa Cruz de La Palma",         lat: 28.68, lon: -17.76),
    TideStation(id: "60", name: "Santa Cruz de Tenerife",         lat: 28.47, lon: -16.25),
    TideStation(id: "25", name: "Santa Uxía de Ribeíra (Ría de Arousa)", lat: 42.55, lon: -8.99),
    TideStation(id: "45", name: "Sancti Petri",                   lat: 36.39, lon: -6.21),
    TideStation(id: "3",  name: "Santander",                      lat: 43.46, lon: -3.80),
    TideStation(id: "27", name: "Sanxenxo (Ría de Pontevedra)",   lat: 42.40, lon: -8.81),
    TideStation(id: "38", name: "Sevilla",                        lat: 37.33, lon: -6.00),
    TideStation(id: "50", name: "Sotogrande",                     lat: 36.28, lon: -5.27),
    TideStation(id: "52", name: "Tánger",                         lat: 35.78, lon: -5.81, tzOverride: "Africa/Casablanca"),
    TideStation(id: "10", name: "Tapia",                          lat: 43.57, lon: -6.94),
    TideStation(id: "48", name: "Tarifa",                         lat: 36.01, lon: -5.61),
    TideStation(id: "29", name: "Vigo",                           lat: 42.24, lon: -8.73),
    TideStation(id: "26", name: "Vilagarcía (Ría de Arousa)",     lat: 42.60, lon: -8.77),
]

// MARK: - Service

struct TidesService {
    static let shared = TidesService()
    private let base = "https://ideihm.covam.es/api-ihm/getmarea"

    /// The two days of tides starting at `date`, with every time already on the port's
    /// own clock (peninsular, canaria, portuguesa o marroquí).
    func tides(for date: Date, stationId: String = "4", stationName: String = "Llanes") async throws -> TidesDayPair {
        let zone = (ihmStations.first { $0.id == stationId })?.timeZone
            ?? TimeZone(identifier: "Europe/Madrid")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone

        let day0 = cal.startOfDay(for: date)
        let day1 = cal.date(byAdding: .day, value: 1, to: day0)!
        let end  = cal.date(byAdding: .day, value: 1, to: day1)!

        // IHM publishes its tables in UTC, so each local day is served by the UTC days
        // that overlap it: at +02:00 the first tide of the day is often still listed on
        // yesterday's table, and the last one spills onto tomorrow's.
        var stamped: [(at: Date, tide: Tide)] = []
        for utcDay in Self.utcDays(from: day0, to: end) {
            for tide in await dayTable(station: stationId, utcDay: utcDay) {
                guard let at = Self.instant(of: tide.time, onUTCDay: utcDay) else { continue }
                stamped.append((at, tide))
            }
        }

        let hhmm = DateFormatter()
        hhmm.locale = Locale(identifier: "en_US_POSIX")
        hhmm.dateFormat = "HH:mm"
        hhmm.timeZone = zone
        let isoDate = ISO8601DateFormatter()
        isoDate.formatOptions = [.withFullDate]
        isoDate.timeZone = zone   // label the day in port time too

        let days = [day0, day1].map { start -> TideDayResult in
            let next = cal.date(byAdding: .day, value: 1, to: start)!
            let tides = stamped
                .filter { $0.at >= start && $0.at < next }
                .sorted { $0.at < $1.at }
                .map { Tide(time: hhmm.string(from: $0.at), height: $0.tide.height, type: $0.tide.type) }
            return TideDayResult(date: isoDate.string(from: start), tides: tides)
        }
        return TidesDayPair(station: stationName, days: days)
    }

    /// One UTC day's table, straight from IHM (times still in UTC, as published).
    /// A published day never changes, so a cache hit is final: no network call, and the
    /// card paints on the first frame.
    private func dayTable(station: String, utcDay: Date) async -> [Tide] {
        let dateStr = Self.utcDayFmt.string(from: utcDay)
        if let cached = TidesDiskCache.load(station: station, day: dateStr) { return cached }

        var comps = URLComponents(string: base)!
        comps.queryItems = [
            URLQueryItem(name: "request", value: "gettide"),
            URLQueryItem(name: "id",      value: station),
            URLQueryItem(name: "format",  value: "json"),
            URLQueryItem(name: "date",    value: dateStr),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let resp = try JSONDecoder().decode(IHMResponse.self, from: data)
            var tideList = resp.mareas?.datos?.marea ?? []
            if tideList.isEmpty, let single = resp.mareas?.datos?.mareaOne {
                tideList = [single]
            }
            let tides = tideList.map {
                Tide(time: $0.hora ?? "—", height: Double($0.altura ?? "0") ?? 0, type: $0.tipo ?? "")
            }
            // Only cache a real answer — an empty day may just be IHM having a bad moment.
            if !tides.isEmpty { TidesDiskCache.save(tides, station: station, day: dateStr) }
            return tides
        } catch {
            return []
        }
    }

    /// UTC midnights of every table needed to cover the local window `[from, to)`.
    private static func utcDays(from: Date, to: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var day = cal.startOfDay(for: from)
        var out: [Date] = []
        while day < to {
            out.append(day)
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }

    /// "HH:mm" read as UTC on `utcDay`. UTC has no DST, so plain arithmetic is exact.
    private static func instant(of hhmm: String, onUTCDay utcDay: Date) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return utcDay.addingTimeInterval(Double(h) * 3600 + Double(m) * 60)
    }

    private static let utcDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

// MARK: - Disk cache

/// Per (station, day) tide tables, kept in the App Group container so the app and the
/// widget share one copy. Entries are immutable, so they are only ever pruned by age.
enum TidesDiskCache {
    private static let folder = "TidesCache"
    /// Days kept around; anything older is no longer reachable from the UI.
    private static let maxAgeDays = 30

    private static func directory() -> URL? {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let base else { return nil }
        let url = base.appendingPathComponent(folder, isDirectory: true)
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static func fileURL(station: String, day: String) -> URL? {
        directory()?.appendingPathComponent("\(station)_\(day).json")
    }

    static func load(station: String, day: String) -> [Tide]? {
        guard let url = fileURL(station: station, day: day),
              let data = try? Data(contentsOf: url),
              let tides = try? JSONDecoder().decode([Tide].self, from: data),
              !tides.isEmpty else { return nil }
        return tides
    }

    static func save(_ tides: [Tide], station: String, day: String) {
        guard let url = fileURL(station: station, day: day),
              let data = try? JSONEncoder().encode(tides) else { return }
        try? data.write(to: url, options: .atomic)
        prune()
    }

    /// Drop files last written more than `maxAgeDays` ago.
    private static func prune() {
        guard let dir = directory() else { return }
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            try? fm.removeItem(at: file)
        }
    }
}

// MARK: - Result types

struct TidesDayPair {
    let station: String
    let days: [TideDayResult]
}

struct TideDayResult: Identifiable {
    var id: String { date }
    let date: String
    let tides: [Tide]
}

// MARK: - IHM JSON models

private struct IHMResponse: Decodable {
    let mareas: IHMMareas?
}

private struct IHMMareas: Decodable {
    let datos: IHMDatos?
}

private struct IHMDatos: Decodable {
    let marea: [IHMTide]?
    let mareaOne: IHMTide?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decode([IHMTide].self, forKey: .marea) {
            marea = arr; mareaOne = nil
        } else if let one = try? c.decode(IHMTide.self, forKey: .marea) {
            marea = nil; mareaOne = one
        } else {
            marea = nil; mareaOne = nil
        }
    }
    enum CodingKeys: String, CodingKey { case marea }
}

private struct IHMTide: Decodable {
    let hora: String?
    let altura: String?
    let tipo: String?
}
