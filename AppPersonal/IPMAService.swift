import Foundation

// IPMA — Instituto Português do Mar e da Atmosfera. Portugal's national weather service,
// whose open data needs no API key: https://api.ipma.pt/
//
// Like the Open-Meteo fallback, everything here is adapted into the very same `Aemet*`
// structs the views and the widget snapshot builder already consume, so no view knows
// which country's service is behind the numbers.
//
// What IPMA publishes, and what we use:
//   · forecast   public-data/forecast/aggregate/{id}.json  — hourly + daily in one file
//   · observation observation/meteorology/stations/…       — hourly, ~200 real stations
//   · warnings   forecast/warnings/warnings_www.json       — by warning area, 3 days
// It does *not* publish tide tables (those belong to the Instituto Hidrográfico and have
// no open API), so the Mareas card stays on Spain's IHM — which does serve Lisboa.
//
// Coverage is the catch: the open catalogue is 35 locations (district capitals plus the
// islands), and `aggregate` only answers for those ids. Anywhere else in Portugal is
// served by Open-Meteo from its coordinate, exactly as elsewhere abroad.

// MARK: - Catalog

/// One of IPMA's forecast locations.
struct IPMALocation: Identifiable, Hashable {
    var id: Int { globalId }
    let globalId: Int
    let name: String
    let lat: Double
    let lon: Double
    /// IPMA warning area this location belongs to (e.g. "LSB"), used to filter warnings.
    let warningArea: String

    /// The `SavedLocation.code` this location is followed under. The `pt-` prefix is what
    /// marks a location as IPMA-served throughout the app — it keeps every existing store
    /// (per-code widget snapshots, pinned stations) working untouched, and AEMET codes are
    /// bare INE digits so the two can never collide.
    var code: String { IPMA.codePrefix + String(globalId) }

    /// Portugal spans three zones, and `globalIdLocal` says which: IPMA's `idRegiao`
    /// (1 continente, 2 Madeira, 3 Açores) is its leading digit. The Azores run an hour
    /// behind Lisboa, so Ponta Delgada on Europe/Lisbon would misprint every sunrise.
    var timeZone: String {
        switch String(globalId).first {
        case "3":  return "Atlantic/Azores"
        case "2":  return "Atlantic/Madeira"
        default:   return "Europe/Lisbon"
        }
    }
}

enum IPMA {
    static let codePrefix = "pt-"

    /// True when a followed location is served by IPMA.
    static func isPortuguese(code: String) -> Bool { code.hasPrefix(codePrefix) }

    static func location(forCode code: String) -> IPMALocation? {
        guard isPortuguese(code: code), let id = Int(code.dropFirst(codePrefix.count)) else { return nil }
        return locations.first { $0.globalId == id }
    }

    /// Catalogue matches for a search box query (accent/case-insensitive). Folds here
    /// rather than through `LocationStore`, which the widget extension doesn't build.
    static func search(_ query: String) -> [IPMALocation] {
        let q = fold(query)
        guard q.count >= 2 else { return [] }
        return locations.filter { fold($0.name).contains(q) }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    /// Catalogue matches shaped as `AemetMunicipio`, so the search boxes and the "add a
    /// place" path treat a Portuguese city exactly like a Spanish one.
    static func searchAsMunicipios(_ query: String) -> [AemetMunicipio] {
        search(query).map {
            AemetMunicipio(codMunicipio: $0.code, nombre: $0.name, lat: $0.lat, lon: $0.lon)
        }
    }

    /// The catalogue location nearest to a coordinate, and how far away it is in km.
    /// Used to resolve a GPS fix taken in Portugal onto the closest IPMA forecast.
    static func nearest(to lat: Double, _ lon: Double) -> (location: IPMALocation, km: Double)? {
        locations
            .map { ($0, haversineKm($0.lat, $0.lon, lat, lon)) }
            .min { $0.1 < $1.1 }
            .map { (location: $0.0, km: $0.1) }
    }

    /// IPMA's open forecast catalogue (`open-data/distrits-islands.json`). Embedded rather
    /// than fetched: it's 35 fixed entries that have to be searchable offline and before
    /// any network call, and they only change when IPMA adds a district capital.
    static let locations: [IPMALocation] = [
        IPMALocation(globalId: 3430100, name: "Angra do Heroísmo",      lat: 38.6700, lon: -27.2200, warningArea: "ACE"),
        IPMALocation(globalId: 1010500, name: "Aveiro",                 lat: 40.6413, lon: -8.6535,  warningArea: "AVR"),
        IPMALocation(globalId: 1020500, name: "Beja",                   lat: 38.0200, lon: -7.8700,  warningArea: "BJA"),
        IPMALocation(globalId: 1030300, name: "Braga",                  lat: 41.5475, lon: -8.4227,  warningArea: "BRG"),
        IPMALocation(globalId: 1040200, name: "Bragança",               lat: 41.8076, lon: -6.7606,  warningArea: "BGC"),
        IPMALocation(globalId: 1050200, name: "Castelo Branco",         lat: 39.8217, lon: -7.4957,  warningArea: "CBO"),
        IPMALocation(globalId: 1060300, name: "Coimbra",                lat: 40.2081, lon: -8.4194,  warningArea: "CBR"),
        IPMALocation(globalId: 1080500, name: "Faro",                   lat: 37.0146, lon: -7.9331,  warningArea: "FAR"),
        IPMALocation(globalId: 2310300, name: "Funchal",                lat: 32.6485, lon: -16.9084, warningArea: "MCS"),
        IPMALocation(globalId: 1090700, name: "Guarda",                 lat: 40.5379, lon: -7.2647,  warningArea: "GDA"),
        IPMALocation(globalId: 1030800, name: "Guimarães",              lat: 41.4434, lon: -8.2938,  warningArea: "BRG"),
        IPMALocation(globalId: 3470100, name: "Horta",                  lat: 38.5363, lon: -28.6315, warningArea: "ACE"),
        IPMALocation(globalId: 1100900, name: "Leiria",                 lat: 39.7473, lon: -8.8069,  warningArea: "LRA"),
        IPMALocation(globalId: 1110600, name: "Lisboa",                 lat: 38.7660, lon: -9.1286,  warningArea: "LSB"),
        IPMALocation(globalId: 1080800, name: "Loulé",                  lat: 37.1397, lon: -8.0202,  warningArea: "FAR"),
        IPMALocation(globalId: 3460200, name: "Madalena",               lat: 38.5325, lon: -28.5237, warningArea: "ACE"),
        IPMALocation(globalId: 1090821, name: "Penhas Douradas",        lat: 40.4075, lon: -7.5665,  warningArea: "GDA"),
        IPMALocation(globalId: 3420300, name: "Ponta Delgada",          lat: 37.7415, lon: -25.6677, warningArea: "AOR"),
        IPMALocation(globalId: 1121400, name: "Portalegre",             lat: 39.2900, lon: -7.4200,  warningArea: "PTG"),
        IPMALocation(globalId: 1081100, name: "Portimão",               lat: 37.1500, lon: -8.5200,  warningArea: "FAR"),
        IPMALocation(globalId: 1131200, name: "Porto",                  lat: 41.1580, lon: -8.6294,  warningArea: "PTO"),
        IPMALocation(globalId: 2320100, name: "Porto Santo",            lat: 33.0700, lon: -16.3400, warningArea: "MPS"),
        IPMALocation(globalId: 1081505, name: "Sagres",                 lat: 37.0168, lon: -8.9403,  warningArea: "FAR"),
        IPMALocation(globalId: 3440100, name: "Santa Cruz da Graciosa", lat: 39.0800, lon: -28.0000, warningArea: "ACE"),
        IPMALocation(globalId: 3480200, name: "Santa Cruz das Flores",  lat: 39.4500, lon: -31.1300, warningArea: "AOC"),
        IPMALocation(globalId: 1141600, name: "Santarém",               lat: 39.2000, lon: -8.7400,  warningArea: "STM"),
        IPMALocation(globalId: 1151200, name: "Setúbal",                lat: 38.5246, lon: -8.8856,  warningArea: "STB"),
        IPMALocation(globalId: 1151300, name: "Sines",                  lat: 37.9560, lon: -8.8643,  warningArea: "STB"),
        IPMALocation(globalId: 3450200, name: "Velas",                  lat: 38.6842, lon: -28.2133, warningArea: "ACE"),
        IPMALocation(globalId: 1160900, name: "Viana do Castelo",       lat: 41.6952, lon: -8.8365,  warningArea: "VCT"),
        IPMALocation(globalId: 1171400, name: "Vila Real",              lat: 41.3053, lon: -7.7440,  warningArea: "VRL"),
        IPMALocation(globalId: 3490100, name: "Vila do Corvo",          lat: 39.6700, lon: -31.1200, warningArea: "AOC"),
        IPMALocation(globalId: 3410100, name: "Vila do Porto",          lat: 36.9563, lon: -25.1409, warningArea: "AOR"),
        IPMALocation(globalId: 1182300, name: "Viseu",                  lat: 40.6585, lon: -7.9120,  warningArea: "VIS"),
        IPMALocation(globalId: 1070500, name: "Évora",                  lat: 38.5701, lon: -7.9104,  warningArea: "EVR"),
    ]
}

// MARK: - Which service serves a Portuguese location

/// Where a Portuguese location's forecast comes from. IPMA is the official service but
/// only forecasts 35 points, so a town 40 km from the nearest district capital is better
/// served by Open-Meteo reading its actual coordinate — which of the two is "right"
/// depends on where you are, so the user picks, in the same sheet that picks an AEMET
/// observation station in Spain.
enum PortugalSource: String, CaseIterable {
    case ipma
    case openMeteo = "openmeteo"
}

extension IPMA {
    /// Beyond this, the nearest district capital is far enough that its forecast is a
    /// different place — Open-Meteo's own coordinate becomes the better default.
    static let nearbyCapitalKm: Double = 25

    /// The source a Portuguese location actually reads from: the user's pick if they made
    /// one, otherwise IPMA when its forecast point is close by and Open-Meteo when not.
    static func source(for loc: SavedLocation) -> PortugalSource {
        if let pinned = pinnedSource(forCode: loc.code) { return pinned }
        guard let point = forecastPoint(for: loc) else { return .openMeteo }
        return point.km <= nearbyCapitalKm ? .ipma : .openMeteo
    }

    /// The IPMA forecast point a location would use, with how far it sits from the
    /// location's own coordinate.
    ///
    /// The distance is always measured, never assumed to be zero for a catalogue code: a
    /// GPS fix in Portugal is stored under the code of its *nearest* capital while keeping
    /// the real coordinate, so Nazaré is a `pt-` Leiria entry standing 28 km from Leiria.
    /// Treating "has a catalogue code" as "is that city" made every such fix read IPMA,
    /// however far away, and the Open-Meteo default never triggered.
    static func forecastPoint(for loc: SavedLocation) -> (location: IPMALocation, km: Double)? {
        if let exact = location(forCode: loc.code) {
            return (exact, haversineKm(exact.lat, exact.lon, loc.lat, loc.lon))
        }
        return nearest(to: loc.lat, loc.lon)
    }

    /// The user's explicit source pick for a location, if any. Stored in the same
    /// per-code map that remembers pinned AEMET stations — it answers the same question
    /// ("where do this place's readings come from"), and the codes can't collide.
    /// It is keyed per catalogue code, so following Leiria *and* standing in Nazaré share
    /// one pick; that only happens once the user overrides the distance-based default.
    static func pinnedSource(forCode code: String) -> PortugalSource? {
        WidgetStore.stationOverride(forCode: code).flatMap(PortugalSource.init(rawValue:))
    }

    static func savePinnedSource(_ source: PortugalSource?, forCode code: String) {
        WidgetStore.saveStationOverride(source?.rawValue, forCode: code)
    }
}

/// Great-circle distance in km. Free function so the widget extension can use it without
/// pulling in CoreLocation.
func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6371.0, p = Double.pi / 180
    let dLat = (lat2 - lat1) * p, dLon = (lon2 - lon1) * p
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * p) * cos(lat2 * p) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, sqrt(a)))
}

// MARK: - Service

struct IPMAService {
    static let shared = IPMAService()

    private let openData = "https://api.ipma.pt/open-data"
    private let publicData = "https://api.ipma.pt/public-data"

    /// Forecast bundle shaped like the AEMET roots the views expect.
    struct Forecast {
        let daily: AemetDailyRoot
        let hourly: AemetHourlyRoot
    }

    // MARK: Forecast

    /// Hourly + daily forecast for a catalogue location. IPMA serves both in one
    /// `aggregate` document: `idPeriodo` 1 marks the hourly rows, 24 the daily ones.
    func forecast(globalId: Int, maxAge: TimeInterval? = nil) async throws -> Forecast {
        let data = try await fetch("\(publicData)/forecast/aggregate/\(globalId).json",
                                   cacheKey: "ipma_fc_\(globalId)", maxAge: maxAge)
        let rows = try JSONDecoder().decode([AggregateRow].self, from: data)
        return Self.adapt(rows)
    }

    // MARK: Observation

    /// The most recent readings from the IPMA station nearest to a coordinate, as an
    /// AEMET-shaped observation record. IPMA publishes one document with every station's
    /// last hours keyed by timestamp, so a single fetch serves any location.
    func observation(lat: Double, lon: Double, maxAge: TimeInterval? = nil) async -> [AemetObservationRecord] {
        guard let stations = try? await stations() else { return [] }
        guard let nearest = stations
            .map({ ($0, haversineKm($0.lat, $0.lon, lat, lon)) })
            .min(by: { $0.1 < $1.1 })?.0 else { return [] }
        guard let data = try? await fetch("\(openData)/observation/meteorology/stations/observations.json",
                                          cacheKey: "ipma_obs", maxAge: maxAge),
              let byHour = try? JSONDecoder().decode([String: [String: ObservationRow?]].self, from: data)
        else { return [] }

        // Oldest → newest, so `AemetSnapshotBuilder`'s "scan back from the newest record"
        // helpers behave exactly as they do with AEMET's own ordering.
        return byHour.keys.sorted().compactMap { hour -> AemetObservationRecord? in
            guard let row = byHour[hour]?[String(nearest.id)] ?? nil else { return nil }
            return AemetObservationRecord(
                fint: Self.obsStamp(hour),
                ta: row.temperatura.flatMap(Self.valid),
                hr: row.humidade.flatMap(Self.valid),
                vv: row.intensidadeVento.flatMap(Self.valid),
                vmax: nil,
                prec: row.precAcumulada.flatMap(Self.valid))
        }
    }

    /// Friendly name of the IPMA station nearest to a coordinate, for the location card.
    func nearestStationName(lat: Double, lon: Double) async -> (name: String, km: Double)? {
        guard let stations = try? await stations() else { return nil }
        return stations
            .map { (name: $0.name, km: haversineKm($0.lat, $0.lon, lat, lon)) }
            .min { $0.km < $1.km }
    }

    /// The observation-station catalogue (GeoJSON), cached on disk for a day.
    private func stations() async throws -> [Station] {
        let data = try await fetch("\(openData)/observation/meteorology/stations/stations.json",
                                   cacheKey: "ipma_stations", maxAge: 24 * 60 * 60)
        return try JSONDecoder().decode([StationFeature].self, from: data).compactMap(Station.init)
    }

    // MARK: Warnings

    /// Active IPMA warnings for a location's warning area, as the same `AemetAlert` the
    /// banner and the widget badge already render. IPMA states every area/type every day
    /// including the green (no warning) ones, so most rows are dropped here.
    func alerts(area: String, maxAge: TimeInterval? = nil) async -> [AemetAlert] {
        guard let data = try? await fetch("\(openData)/forecast/warnings/warnings_www.json",
                                          cacheKey: "ipma_warnings", maxAge: maxAge),
              let rows = try? JSONDecoder().decode([WarningRow].self, from: data)
        else { return [] }
        let now = Date()
        var best: [String: AemetAlert] = [:]     // phenomenon → strongest active warning
        for row in rows where row.idAreaAviso == area {
            let level = Self.level(row.awarenessLevelID)
            guard level > .verde else { continue }
            let onset = Self.parseStamp(row.startTime)
            let expires = Self.parseStamp(row.endTime)
            if let expires, expires < now { continue }
            let phenomenon = Self.phenomenon(row.awarenessTypeName)
            let alert = AemetAlert(
                phenomenon: phenomenon,
                event: row.text?.isEmpty == false ? row.text! : phenomenon,
                level: level,
                areaDesc: Self.areaName(area),
                onset: onset,
                expires: expires,
                sfSymbol: Self.symbol(row.awarenessTypeName))
            if let existing = best[phenomenon], existing.level >= alert.level { continue }
            best[phenomenon] = alert
        }
        return best.values.sorted { $0.level > $1.level }
    }

    // MARK: - One-stop load for a Portuguese location

    /// Everything the Tiempo tab and the widget need for a Portuguese location, from
    /// whichever service it is set to read. Both callers go through here so the app and
    /// the widget can never end up showing two different sources for the same place.
    struct Bundle {
        let daily: AemetDailyRoot?
        let hourly: AemetHourlyRoot?
        let obs: [AemetObservationRecord]
        let alerts: [AemetAlert]
        /// What to credit on screen, e.g. "IPMA · Porto" or "Open-Meteo".
        let sourceLabel: String
    }

    static func load(for loc: SavedLocation, maxAge: TimeInterval?) async -> Bundle? {
        // Warnings are IPMA's either way: they're official, and Open-Meteo has none.
        let area = IPMA.forecastPoint(for: loc)?.location.warningArea
        async let alertTask: [AemetAlert] = {
            guard let area else { return [] }
            return await shared.alerts(area: area, maxAge: maxAge)
        }()

        switch IPMA.source(for: loc) {
        case .ipma:
            guard let point = IPMA.forecastPoint(for: loc) else { return nil }
            async let fcTask = try? await shared.forecast(globalId: point.location.globalId, maxAge: maxAge)
            async let obsTask = await shared.observation(lat: loc.lat, lon: loc.lon, maxAge: maxAge)
            guard let fc = await fcTask else { return nil }
            return Bundle(daily: fc.daily, hourly: fc.hourly, obs: await obsTask,
                          alerts: await alertTask,
                          sourceLabel: "IPMA · \(point.location.name)")
        case .openMeteo:
            guard let fc = await OpenMeteoService.shared.fetchForecast(lat: loc.lat, lon: loc.lon) else { return nil }
            return Bundle(daily: fc.daily, hourly: fc.hourly, obs: fc.obs,
                          alerts: await alertTask, sourceLabel: "Open-Meteo")
        }
    }

    // MARK: - Fetch + disk cache

    /// GET with the same disk cache AEMET uses (App Group, shared with the widget):
    /// serve a cached body younger than `maxAge` without a request, and fall back to a
    /// stale one when the network fails.
    private func fetch(_ urlString: String, cacheKey: String, maxAge: TimeInterval?) async throws -> Data {
        let cached = AemetDiskCache.load(cacheKey)
        if let maxAge, let c = cached, c.age < maxAge { return c.data }
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            AemetDiskCache.save(cacheKey, data: data)
            return data
        } catch {
            if let c = cached { return c.data }
            throw error
        }
    }

    // MARK: - Raw IPMA shapes

    /// One row of `forecast/aggregate`. Hourly rows carry `tMed`/`hR`, daily ones
    /// `tMin`/`tMax`/`iUv`; both share the weather-type and wind fields.
    private struct AggregateRow: Decodable {
        let idPeriodo: Int?
        let dataPrev: String?
        let idTipoTempo: Int?
        let probabilidadePrecipita: String?
        let ddVento: String?
        let ffVento: String?        // km/h, hourly
        let tMed: String?
        let tMin: String?
        let tMax: String?
        let hR: String?
        let iUv: String?
        let classWindSpeed: Int?
        let idFfxVento: Int?
    }

    private struct StationFeature: Decodable {
        struct Geometry: Decodable { let coordinates: [Double] }
        struct Properties: Decodable { let idEstacao: Int; let localEstacao: String }
        let geometry: Geometry
        let properties: Properties
    }

    private struct Station {
        let id: Int, name: String, lat: Double, lon: Double
        init?(_ f: StationFeature) {
            guard f.geometry.coordinates.count >= 2 else { return nil }
            id = f.properties.idEstacao
            name = f.properties.localEstacao
            lon = f.geometry.coordinates[0]
            lat = f.geometry.coordinates[1]
        }
    }

    private struct ObservationRow: Decodable {
        let temperatura: Double?
        let humidade: Double?
        let intensidadeVento: Double?    // m/s (intensidadeVentoKM carries the km/h twin)
        let precAcumulada: Double?
        let pressao: Double?
    }

    private struct WarningRow: Decodable {
        let text: String?
        let awarenessTypeName: String?
        let idAreaAviso: String?
        let awarenessLevelID: String?
        let startTime: String?
        let endTime: String?
    }

    // MARK: - Adapt IPMA → AEMET structs

    private static func adapt(_ rows: [AggregateRow]) -> Forecast {
        let origen = AemetOrigen(productor: "IPMA — Instituto Português do Mar e da Atmosfera",
                                 web: "https://www.ipma.pt", enlace: nil, notaLegal: nil,
                                 copyright: "© IPMA", licencia: "CC BY-NC-SA")

        // --- Hourly (idPeriodo 1), grouped by day ---
        var byDay: [String: (t: [AemetPeriodValue], sky: [AemetPeriodValue], prob: [AemetPeriodValue])] = [:]
        var dayOrder: [String] = []
        for row in rows where row.idPeriodo == 1 {
            guard let stamp = row.dataPrev, stamp.count >= 13 else { continue }
            let day = String(stamp.prefix(10))
            let hour = Int(stamp.dropFirst(11).prefix(2)) ?? 0
            if byDay[day] == nil { byDay[day] = ([], [], []); dayOrder.append(day) }
            let hh = String(format: "%02d", hour)
            if let t = row.tMed.flatMap(Double.init) {
                byDay[day]!.t.append(AemetPeriodValue(periodo: hh, value: String(Int(t.rounded()))))
            }
            if let type = row.idTipoTempo, type > 0 {
                byDay[day]!.sky.append(AemetPeriodValue(periodo: hh,
                                                        value: skyCode(type, day: isDaylight(hour)),
                                                        descripcion: skyText(type)))
            }
            if let p = row.probabilidadePrecipita.flatMap(Double.init), p >= 0 {
                // The hourly strip looks probabilities up by "HHHH" hour range.
                let range = String(format: "%02d%02d", hour, (hour + 1) % 24)
                byDay[day]!.prob.append(AemetPeriodValue(periodo: range, value: String(Int(p.rounded()))))
            }
        }
        let hourlyDays = dayOrder.sorted().map { day -> AemetHourlyDay in
            let e = byDay[day]!
            return AemetHourlyDay(fecha: day, temperatura: e.t, estadoCielo: e.sky, probPrecipitacion: e.prob)
        }
        let hourly = AemetHourlyRoot(nombre: nil, provincia: nil, elaborado: isoNow(),
                                     prediccion: AemetHourlyPred(dia: hourlyDays), origen: origen)

        // Strongest hourly wind of each day, as a fallback for the daily rows: IPMA leaves
        // `classWindSpeed` null on most days (Porto has it on none), which would leave the
        // daily card with no wind at all even though the hourly rows carry km/h all along.
        var windByDay: [String: (kmh: Double, dir: String)] = [:]
        for row in rows where row.idPeriodo == 1 {
            guard let stamp = row.dataPrev, let ff = row.ffVento.flatMap(Double.init), ff >= 0 else { continue }
            let day = String(stamp.prefix(10))
            if let existing = windByDay[day], existing.kmh >= ff { continue }
            windByDay[day] = (ff, row.ddVento ?? "")
        }

        // --- Daily (idPeriodo 24) ---
        let dailyDays = rows.filter { $0.idPeriodo == 24 }
            .sorted { ($0.dataPrev ?? "") < ($1.dataPrev ?? "") }
            .map { row -> AemetDailyDay in
                let day = String((row.dataPrev ?? "").prefix(10))
                let sky = row.idTipoTempo.flatMap { $0 > 0 ? $0 : nil }
                let hourlyWind = windByDay[day]
                return AemetDailyDay(
                    fecha: day,
                    temperatura: AemetMinMax(maxima: row.tMax.flatMap(Double.init),
                                             minima: row.tMin.flatMap(Double.init)),
                    sensTermica: nil,
                    humedadRelativa: nil,
                    estadoCielo: sky.map { [AemetPeriodValue(periodo: "00-24", value: skyCode($0, day: true),
                                                             descripcion: skyText($0))] },
                    probPrecipitacion: (row.probabilidadePrecipita.flatMap(Double.init)).flatMap {
                        $0 < 0 ? nil : [AemetPeriodValue(periodo: "00-24", value: String(Int($0.rounded())))]
                    },
                    rachaMax: nil,
                    // The day's strongest hourly wind when there is one; otherwise IPMA's
                    // wind *class* (1–4), read at the midpoint of its km/h band.
                    viento: dailyWind(hourly: hourlyWind, cls: row.classWindSpeed, dir: row.ddVento),
                    cotaNieveProv: nil,
                    uvMax: row.iUv.flatMap(Double.init).map { Int($0.rounded()) })
            }
        let daily = AemetDailyRoot(nombre: nil, provincia: nil, elaborado: isoNow(),
                                   prediccion: AemetDailyPred(dia: dailyDays), origen: origen)

        return Forecast(daily: daily, hourly: hourly)
    }

    /// Rough day/night split for picking the night variant of a sky icon. IPMA gives no
    /// is-day flag; the app's own sunrise/sunset engine isn't reachable from the widget
    /// snapshot path, and being an hour off only swaps a sun glyph for a moon at dusk.
    private static func isDaylight(_ hour: Int) -> Bool { (7...20).contains(hour) }

    /// IPMA `idTipoTempo` → the AEMET-style sky code `WeatherIconView` understands
    /// (numeric base plus an optional "n" night suffix).
    private static func skyCode(_ type: Int, day: Bool) -> String {
        let base: Int
        switch type {
        case 1:            base = 11   // céu limpo
        case 2, 3:         base = 13   // pouco / parcialmente nublado
        case 4, 5, 25, 27: base = 15   // muito nublado ou encoberto
        case 6, 8, 11:     base = 44   // aguaceiros / chuva forte
        case 7:            base = 43   // aguaceiros fracos
        case 9, 12, 14:    base = 24   // chuva, períodos de chuva
        case 10, 13, 15:   base = 43   // chuva fraca, chuvisco
        case 16, 17, 26:   base = 81   // neblina, nevoeiro
        case 18, 28:       base = 34   // neve
        case 19, 20, 23:   base = 52   // trovoada
        case 21:           base = 62   // granizo
        case 22:           base = 11   // geada (clear, cold night)
        case 24:           base = 15   // nebulosidade convectiva
        case 29, 30:       base = 34   // chuva e neve
        default:           base = 15
        }
        return day ? "\(base)" : "\(base)n"
    }

    /// Sky description, in the app's language rather than IPMA's Portuguese, so the card
    /// reads the same for a Portuguese city as for a Spanish one.
    private static func skyText(_ type: Int) -> String {
        switch type {
        case 1:          return String(localized: "Despejado")
        case 2:          return String(localized: "Poco nuboso")
        case 3, 25:      return String(localized: "Parcialmente nuboso")
        case 4, 5, 27:   return String(localized: "Cubierto")
        case 6, 9:       return String(localized: "Chubascos")
        case 7, 10, 13:  return String(localized: "Lluvia débil")
        case 8, 11, 14:  return String(localized: "Lluvia fuerte")
        case 12:         return String(localized: "Periodos de lluvia")
        case 15:         return String(localized: "Llovizna")
        case 16:         return String(localized: "Neblina")
        case 17, 26:     return String(localized: "Niebla")
        case 18:         return String(localized: "Nieve")
        case 19:         return String(localized: "Tormenta")
        case 20, 23:     return String(localized: "Chubascos con tormenta")
        case 21:         return String(localized: "Granizo")
        case 22:         return String(localized: "Helada")
        case 24:         return String(localized: "Nubosidad de evolución")
        case 28:         return String(localized: "Chubascos de nieve")
        case 29, 30:     return String(localized: "Lluvia y nieve")
        default:         return "—"
        }
    }

    private static func dailyWind(hourly: (kmh: Double, dir: String)?, cls: Int?, dir: String?) -> [AemetWindEntry]? {
        if let hourly {
            return [AemetWindEntry(periodo: "00-24", velocidad: String(Int(hourly.kmh.rounded())),
                                   direccion: hourly.dir.isEmpty ? (dir ?? "") : hourly.dir)]
        }
        guard let cls else { return nil }
        return [AemetWindEntry(periodo: "00-24", velocidad: String(windClassKmh(cls)), direccion: dir ?? "")]
    }

    /// Midpoint km/h of IPMA's daily wind classes (1: <15, 2: 15–35, 3: 35–55, 4: >55).
    private static func windClassKmh(_ cls: Int) -> Int {
        switch cls {
        case 1:  return 10
        case 2:  return 25
        case 3:  return 45
        default: return 65
        }
    }

    private static func level(_ id: String?) -> AemetAlertLevel {
        switch (id ?? "").lowercased() {
        case "yellow": return .amarillo
        case "orange": return .naranja
        case "red":    return .rojo
        default:       return .verde
        }
    }

    /// IPMA's Portuguese warning types, in the app's language.
    private static func phenomenon(_ name: String?) -> String {
        switch name ?? "" {
        case "Agitação Marítima": return String(localized: "Estado de la mar")
        case "Nevoeiro":          return String(localized: "Nieblas")
        case "Neve":              return String(localized: "Nevadas")
        case "Precipitação":      return String(localized: "Lluvias")
        case "Tempo Frio":        return String(localized: "Temperaturas mínimas")
        case "Tempo Quente":      return String(localized: "Temperaturas máximas")
        case "Trovoada":          return String(localized: "Tormentas")
        case "Vento":             return String(localized: "Vientos")
        default:                  return name ?? String(localized: "Aviso")
        }
    }

    /// Same SF Symbols the AEMET warnings use, so both countries' banners read alike.
    private static func symbol(_ name: String?) -> String {
        switch name ?? "" {
        case "Agitação Marítima": return "water.waves"
        case "Nevoeiro":          return "cloud.fog.fill"
        case "Neve":              return "snowflake"
        case "Precipitação":      return "cloud.rain.fill"
        case "Tempo Frio":        return "thermometer.snowflake"
        case "Tempo Quente":      return "thermometer.sun.fill"
        case "Trovoada":          return "cloud.bolt.rain.fill"
        case "Vento":             return "wind"
        default:                  return "exclamationmark.triangle.fill"
        }
    }

    /// Warning-area code → the name IPMA gives it (districts and island groups).
    private static func areaName(_ area: String) -> String {
        IPMA.locations.first { $0.warningArea == area }.map { $0.name } ?? area
    }

    // MARK: - Timestamps

    /// IPMA stamps are local Portuguese time without an offset ("2026-08-08T15:00").
    private static let ipmaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Lisbon")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static func parseStamp(_ s: String?) -> Date? {
        guard let s else { return nil }
        let padded = s.count == 16 ? s + ":00" : s      // warnings drop the seconds
        return ipmaFormatter.date(from: padded)
    }

    /// Re-stamp an IPMA observation hour as the timezone-less **UTC** string AEMET uses,
    /// since `AemetSnapshotBuilder.parseObsDate` reads `fint` as UTC when judging whether
    /// a reading is recent enough to be "now".
    private static func obsStamp(_ hour: String) -> String {
        guard let date = parseStamp(hour) else { return hour }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }

    /// IPMA marks a missing reading as -99 rather than omitting it.
    private static func valid(_ v: Double) -> Double? { v <= -90 ? nil : v }

    private static func isoNow() -> String { ISO8601DateFormatter().string(from: Date()) }
}
