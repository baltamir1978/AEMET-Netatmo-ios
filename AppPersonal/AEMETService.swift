import Foundation

/// Direct client for AEMET OpenData API.
/// Two-step pattern: first call returns a `datos` URL, then fetch that URL.
struct AEMETService {
    static let shared = AEMETService()
    let base = "https://opendata.aemet.es/opendata/api"

    // Read from the shared App Group so this service compiles & runs inside the
    // widget extension too (the app mirrors `AppConfiguration.aemetApiKey` there).
    private var apiKey: String { WidgetStore.loadAemetApiKey() ?? "" }

    // MARK: - Forecast
    //
    // AEMET enforces strict request limits, so every endpoint persists its last
    // good payload to disk. Pass `maxAge` to reuse that cache without hitting the
    // network when it's still fresh; if a live fetch fails (limit reached / offline)
    // we fall back to the cached payload instead of throwing, so the UI keeps the
    // previous measurements until a refresh actually succeeds.

    func forecastDaily(municipio: String, maxAge: TimeInterval? = nil) async throws -> AemetDailyRoot {
        let key = "diaria_\(municipio)"
        let cached = AemetDiskCache.load(key)
        if let maxAge, let c = cached, c.age < maxAge, let root = try? Self.decodeDaily(c.data) {
            return root
        }
        do {
            let dataURL = try await fetchDataURL("\(base)/prediccion/especifica/municipio/diaria/\(municipio)")
            let raw = try await fetchRaw(dataURL)
            let root = try Self.decodeDaily(raw)
            AemetDiskCache.save(key, data: raw)
            return root
        } catch {
            if let c = cached, let root = try? Self.decodeDaily(c.data) { return root }
            throw error
        }
    }

    func forecastHourly(municipio: String, maxAge: TimeInterval? = nil) async throws -> AemetHourlyRoot {
        let key = "horaria_\(municipio)"
        let cached = AemetDiskCache.load(key)
        if let maxAge, let c = cached, c.age < maxAge, let root = try? Self.decodeHourly(c.data) {
            return root
        }
        do {
            let dataURL = try await fetchDataURL("\(base)/prediccion/especifica/municipio/horaria/\(municipio)")
            let raw = try await fetchRaw(dataURL)
            let root = try Self.decodeHourly(raw)
            AemetDiskCache.save(key, data: raw)
            return root
        } catch {
            if let c = cached, let root = try? Self.decodeHourly(c.data) { return root }
            throw error
        }
    }

    func observation(idema: String, maxAge: TimeInterval? = nil) async throws -> [AemetObservationRecord] {
        let key = "obs_\(idema)"
        let cached = AemetDiskCache.load(key)
        if let maxAge, let c = cached, c.age < maxAge,
           let recs = try? JSONDecoder().decode([AemetObservationRecord].self, from: c.data) {
            return recs
        }
        do {
            let dataURL = try await fetchDataURL("\(base)/observacion/convencional/datos/estacion/\(idema)")
            let raw = try await fetchRaw(dataURL)
            let recs = try JSONDecoder().decode([AemetObservationRecord].self, from: raw)
            AemetDiskCache.save(key, data: raw)
            return recs
        } catch {
            if let c = cached,
               let recs = try? JSONDecoder().decode([AemetObservationRecord].self, from: c.data) { return recs }
            throw error
        }
    }

    // AEMET returns an array; fall back to a single object for some edge cases.
    private static func decodeDaily(_ data: Data) throws -> AemetDailyRoot {
        let dec = JSONDecoder()
        if let arr = try? dec.decode([AemetDailyRoot].self, from: data), let first = arr.first { return first }
        if let single = try? dec.decode(AemetDailyRoot.self, from: data) { return single }
        let arr = try dec.decode([AemetDailyRoot].self, from: data)   // re-decode to surface the real error
        guard let first = arr.first else { throw AEMETError.noData("Predicción diaria sin datos") }
        return first
    }

    private static func decodeHourly(_ data: Data) throws -> AemetHourlyRoot {
        let dec = JSONDecoder()
        if let arr = try? dec.decode([AemetHourlyRoot].self, from: data), let first = arr.first { return first }
        if let single = try? dec.decode(AemetHourlyRoot.self, from: data) { return single }
        let arr = try dec.decode([AemetHourlyRoot].self, from: data)
        guard let first = arr.first else { throw AEMETError.noData("Predicción horaria sin datos") }
        return first
    }

    // MARK: - Synchronous cache reads
    //
    // Let a view paint instantly from the last good payload on launch (no await,
    // no network) so the screen never flashes blank before the live refresh lands.

    func cachedDaily(municipio: String) -> AemetDailyRoot? {
        guard let c = AemetDiskCache.load("diaria_\(municipio)") else { return nil }
        return try? Self.decodeDaily(c.data)
    }

    func cachedHourly(municipio: String) -> AemetHourlyRoot? {
        guard let c = AemetDiskCache.load("horaria_\(municipio)") else { return nil }
        return try? Self.decodeHourly(c.data)
    }

    func cachedObservation(idema: String) -> [AemetObservationRecord]? {
        guard let c = AemetDiskCache.load("obs_\(idema)") else { return nil }
        return try? JSONDecoder().decode([AemetObservationRecord].self, from: c.data)
    }

    // MARK: - Municipality catalog

    func allMunicipios() async throws -> [AemetMunicipio] {
        let url = "\(base)/maestro/municipios"
        let dataURL = try await fetchDataURL(url)
        return try await fetchJSON(dataURL)
    }

    func allStations() async throws -> [AemetStation] {
        let url = "\(base)/valores/climatologicos/inventarioestaciones/todasestaciones"
        let dataURL = try await fetchDataURL(url)
        return try await fetchJSON(dataURL)
    }

    /// Stations that actually publish real-time observations (idema + decimal coords),
    /// derived from the live network `observacion/convencional/todas`. Unlike
    /// `allStations()` (the *climatological* inventory), this excludes stations that never
    /// report hourly data — e.g. San Pablo de los Montes (3298X), whose data endpoint 404s —
    /// so the nearest match to a coordinate always has humidity/wind. The set of reporting
    /// stations barely changes, so the payload is disk-cached (~24 h by default).
    func observationStations(maxAge: TimeInterval = 24 * 60 * 60) async throws -> [AemetLiveStation] {
        let key = "obs_stations"
        let cached = AemetDiskCache.load(key)
        if let c = cached, c.age < maxAge,
           let recs = try? JSONDecoder().decode([AemetObservationRecord].self, from: c.data) {
            return Self.dedupeStations(recs)
        }
        do {
            let dataURL = try await fetchDataURL("\(base)/observacion/convencional/todas")
            let raw = try await fetchRaw(dataURL)
            let recs = try JSONDecoder().decode([AemetObservationRecord].self, from: raw)
            AemetDiskCache.save(key, data: raw)
            return Self.dedupeStations(recs)
        } catch {
            if let c = cached,
               let recs = try? JSONDecoder().decode([AemetObservationRecord].self, from: c.data) {
                return Self.dedupeStations(recs)
            }
            throw error
        }
    }

    /// One entry per station (first record wins; a station repeats its coords across its
    /// hourly records), keeping only those with a usable idema and decimal position.
    private static func dedupeStations(_ recs: [AemetObservationRecord]) -> [AemetLiveStation] {
        var byId: [String: AemetLiveStation] = [:]
        for r in recs {
            guard let id = r.idema, let la = r.lat, let lo = r.lon, byId[id] == nil else { continue }
            byId[id] = AemetLiveStation(indicativo: id, nombre: r.ubi ?? id, lat: la, lon: lo, alt: r.alt)
        }
        return Array(byId.values)
    }

    // MARK: - Private helpers

    func fetchDataURL(_ path: String) async throws -> URL {
        guard !apiKey.isEmpty else { throw AEMETError.notConfigured }
        var comps = URLComponents(string: path)!
        comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "api_key", value: apiKey)]
        let url = comps.url!

        // AEMET enforces a per-minute limit and answers a burst with 429 — sometimes
        // as the HTTP status, sometimes as `estado: 429` in the envelope body. Both
        // clear within a few seconds, so retry with backoff before surfacing the error
        // (a fresh install has no disk cache to fall back on).
        let backoff: [TimeInterval] = [0, 2.5, 5]
        var lastError: Error = AEMETError.rateLimited
        for delay in backoff {
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            // Space every keyed call so a multi-city / multi-endpoint refresh never bursts.
            await AEMETThrottle.shared.wait()
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
                lastError = AEMETError.rateLimited
                continue
            }
            let envelope = try JSONDecoder().decode(AEMETEnvelope.self, from: data)
            if envelope.estado == 429 {
                lastError = AEMETError.rateLimited
                continue
            }
            guard let urlStr = envelope.datos, let dataURL = URL(string: urlStr) else {
                throw AEMETError.noData(envelope.descripcion ?? "Sin datos")
            }
            return dataURL
        }
        throw lastError
    }

    private func fetchRaw(_ url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        // AEMET's datos URLs sometimes return ISO-8859-1 encoded JSON instead of UTF-8.
        // JSONDecoder only accepts UTF-8, so re-encode when needed.
        if String(data: data, encoding: .utf8) != nil { return data }
        guard let str = String(data: data, encoding: .isoLatin1),
              let utf8Data = str.data(using: .utf8) else { return data }
        return utf8Data
    }

    private func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        let data = try await fetchRaw(url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Request throttle

/// Serialises AEMET's keyed requests so bursts (parallel endpoints, multi-city
/// widget refresh) stay under the per-minute limit. Each caller reserves the next
/// time slot before suspending, so concurrent callers space out predictably.
actor AEMETThrottle {
    static let shared = AEMETThrottle()
    private var lastSlot = Date.distantPast
    private let minInterval: TimeInterval = 1.2

    func wait() async {
        let now = Date()
        let slot = max(now, lastSlot.addingTimeInterval(minInterval))
        lastSlot = slot                                   // reserve before awaiting
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

// MARK: - Disk cache

/// Persists each AEMET endpoint's last good payload to Application Support so the
/// app can throttle requests and survive launches without re-hitting the API.
enum AemetDiskCache {
    private static let folder = "AemetCache"

    private static func directory() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent(folder, isDirectory: true)
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static func fileURL(_ key: String) -> URL? {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory()?.appendingPathComponent("\(safe).json")
    }

    /// Cached payload plus its age in seconds, or nil when absent.
    static func load(_ key: String) -> (data: Data, age: TimeInterval)? {
        guard let url = fileURL(key),
              let data = try? Data(contentsOf: url),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return (data, Date().timeIntervalSince(modified))
    }

    static func save(_ key: String, data: Data) {
        guard let url = fileURL(key) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Errors

enum AEMETError: LocalizedError {
    case notConfigured
    case noData(String)
    case rateLimited
    var errorDescription: String? {
        switch self {
        case .notConfigured:   return "Clave API de AEMET no configurada. Ve a Ajustes."
        case .noData(let msg): return "AEMET: \(msg)"
        case .rateLimited:     return "AEMET: demasiadas peticiones, espera un momento."
        }
    }
}

// MARK: - AEMET envelope

struct AEMETEnvelope: Decodable {
    let descripcion: String?
    let estado: Int?
    let datos: String?
    let metadatos: String?
}

// MARK: - Daily forecast models

struct AemetDailyRoot: Decodable {
    let nombre: String?
    let provincia: String?
    let elaborado: String?
    let prediccion: AemetDailyPred?
    let origen: AemetOrigen?
}

struct AemetDailyPred: Decodable {
    let dia: [AemetDailyDay]?
}

struct AemetDailyDay: Decodable {
    let fecha: String?
    let temperatura: AemetMinMax?
    let sensTermica: AemetMinMax?
    let humedadRelativa: AemetMinMax?
    let estadoCielo: [AemetPeriodValue]?
    let probPrecipitacion: [AemetPeriodValue]?
    let rachaMax: [AemetPeriodValue]?
    let viento: [AemetWindEntry]?
    let cotaNieveProv: [AemetPeriodValue]?
    let uvMax: Int?
}

// MARK: - Hourly forecast models

struct AemetHourlyRoot: Decodable {
    let nombre: String?
    let provincia: String?
    let elaborado: String?
    let prediccion: AemetHourlyPred?
    let origen: AemetOrigen?
}

struct AemetHourlyPred: Decodable {
    let dia: [AemetHourlyDay]?
}

struct AemetHourlyDay: Decodable {
    let fecha: String?
    let temperatura: [AemetPeriodValue]?
    let estadoCielo: [AemetPeriodValue]?
    let probPrecipitacion: [AemetPeriodValue]?
}

// MARK: - Shared sub-models

struct AemetPeriodValue: Decodable {
    let periodo: String?
    let value: String?
    let descripcion: String?

    // AEMET inconsistently returns 'value' as String or Int depending on field/version
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        periodo     = try c.decodeIfPresent(String.self, forKey: .periodo)
        descripcion = try c.decodeIfPresent(String.self, forKey: .descripcion)
        if let s = try? c.decodeIfPresent(String.self, forKey: .value) {
            value = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .value) {
            value = String(i)
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .value) {
            value = String(d)
        } else {
            value = nil
        }
    }

    private enum CodingKeys: String, CodingKey { case periodo, value, descripcion }

    // Direct constructor (used to synthesize forecasts from the Open-Meteo fallback).
    init(periodo: String?, value: String?, descripcion: String? = nil) {
        self.periodo = periodo
        self.value = value
        self.descripcion = descripcion
    }
}

struct AemetWindEntry: Decodable {
    let periodo: String?
    let velocidad: String?
    let direccion: String?

    // 'velocidad' sometimes comes as Int
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        periodo   = try c.decodeIfPresent(String.self, forKey: .periodo)
        direccion = try c.decodeIfPresent(String.self, forKey: .direccion)
        if let s = try? c.decodeIfPresent(String.self, forKey: .velocidad) {
            velocidad = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .velocidad) {
            velocidad = String(i)
        } else {
            velocidad = nil
        }
    }

    private enum CodingKeys: String, CodingKey { case periodo, velocidad, direccion }

    // Direct constructor (used to synthesize forecasts from the Open-Meteo fallback).
    init(periodo: String?, velocidad: String?, direccion: String?) {
        self.periodo = periodo
        self.velocidad = velocidad
        self.direccion = direccion
    }
}

struct AemetMinMax: Decodable {
    let maxima: Double?
    let minima: Double?
}

struct AemetOrigen: Decodable {
    let productor: String?
    let web: String?
    let enlace: String?
    let notaLegal: String?
    let copyright: String?
    let licencia: String?
}

// MARK: - Observation

struct AemetObservationRecord: Decodable {
    let idema: String?
    let fint: String?
    let ta: Double?
    let hr: Double?
    let prec: Double?
    let vv: Double?
    let vmax: Double?
    let dv: Double?
    let dmax: Double?
    let pres: Double?
    let tpr: Double?
    let vis: Double?
    let inso: Double?
    let tss5cm: Double?
    let tss20cm: Double?
    let alt: Double?
    let lat: Double?
    let lon: Double?
    let ubi: String?
    let tamin: Double?
    let tamax: Double?

    /// Synthetic "current conditions" record for the Open-Meteo fallback (which has no
    /// physical station). Carries only the fields the hero card reads; the rest are nil.
    init(fint: String?, ta: Double?, hr: Double?, vv: Double?, vmax: Double?, prec: Double?) {
        self.idema = nil; self.fint = fint; self.ta = ta; self.hr = hr; self.prec = prec
        self.vv = vv; self.vmax = vmax; self.dv = nil; self.dmax = nil; self.pres = nil
        self.tpr = nil; self.vis = nil; self.inso = nil; self.tss5cm = nil; self.tss20cm = nil
        self.alt = nil; self.lat = nil; self.lon = nil; self.ubi = nil
        self.tamin = nil; self.tamax = nil
    }
}

// MARK: - Catalog

struct AemetMunicipio: Decodable, Identifiable {
    var id: String { codMunicipio }
    /// Bare forecast code, e.g. "28079" (AEMET's maestro reports it as "id28079").
    let codMunicipio: String
    let nombre: String
    let lat: Double?
    let lon: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case nombre
        case latitudDec = "latitud_dec"
        case longitudDec = "longitud_dec"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = try c.decode(String.self, forKey: .id)
        codMunicipio = rawId.hasPrefix("id") ? String(rawId.dropFirst(2)) : rawId
        nombre = try c.decode(String.self, forKey: .nombre)
        lat = (try? c.decode(String.self, forKey: .latitudDec)).flatMap(Double.init)
        lon = (try? c.decode(String.self, forKey: .longitudDec)).flatMap(Double.init)
    }
}

struct AemetStation: Decodable, Identifiable {
    var id: String { indicativo }
    let indicativo: String
    let nombre: String
    let latitud: String?
    let longitud: String?
    let altitud: String?
    let provincia: String?
}

/// A real-time observation station (decimal coords) distilled from the live network.
/// Mirrors the fields `LocationStore.nearestStation` needs from `AemetStation`.
struct AemetLiveStation {
    let indicativo: String
    let nombre: String
    let lat: Double
    let lon: Double
    /// Station altitude in metres — the station picker shows it, since in mountain country
    /// the nearest station can sit on the far side of a ridge (or 400 m below you).
    let alt: Double?
}
