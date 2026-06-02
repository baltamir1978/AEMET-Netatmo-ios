import Foundation

/// Direct client for AEMET OpenData API.
/// Two-step pattern: first call returns a `datos` URL, then fetch that URL.
struct AEMETService {
    static let shared = AEMETService()
    private let base = "https://opendata.aemet.es/opendata/api"

    private var apiKey: String { AppConfiguration.shared.aemetApiKey }

    // MARK: - Forecast

    func forecastDaily(municipio: String) async throws -> AemetDailyRoot {
        let url = "\(base)/prediccion/especifica/municipio/diaria/\(municipio)"
        let dataURL = try await fetchDataURL(url)
        let raw = try await fetchRaw(dataURL)
        let dec = JSONDecoder()
        // AEMET returns an array; fall back to single object for some edge cases
        if let arr = try? dec.decode([AemetDailyRoot].self, from: raw), let first = arr.first { return first }
        if let single = try? dec.decode(AemetDailyRoot.self, from: raw) { return single }
        // If both fail, decode array again to surface the real error
        let arr = try dec.decode([AemetDailyRoot].self, from: raw)
        guard let first = arr.first else { throw AEMETError.noData("Predicción diaria sin datos") }
        return first
    }

    func forecastHourly(municipio: String) async throws -> AemetHourlyRoot {
        let url = "\(base)/prediccion/especifica/municipio/horaria/\(municipio)"
        let dataURL = try await fetchDataURL(url)
        let raw = try await fetchRaw(dataURL)
        let dec = JSONDecoder()
        if let arr = try? dec.decode([AemetHourlyRoot].self, from: raw), let first = arr.first { return first }
        if let single = try? dec.decode(AemetHourlyRoot.self, from: raw) { return single }
        let arr = try dec.decode([AemetHourlyRoot].self, from: raw)
        guard let first = arr.first else { throw AEMETError.noData("Predicción horaria sin datos") }
        return first
    }

    func observation(idema: String) async throws -> [AemetObservationRecord] {
        let url = "\(base)/observacion/convencional/datos/estacion/\(idema)"
        let dataURL = try await fetchDataURL(url)
        return try await fetchJSON(dataURL)
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

    // MARK: - Private helpers

    private func fetchDataURL(_ path: String) async throws -> URL {
        guard !apiKey.isEmpty else { throw AEMETError.notConfigured }
        var comps = URLComponents(string: path)!
        comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "api_key", value: apiKey)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        if let http = resp as? HTTPURLResponse, http.statusCode == 429 { throw AEMETError.rateLimited }
        let envelope = try JSONDecoder().decode(AEMETEnvelope.self, from: data)
        guard let urlStr = envelope.datos, let url = URL(string: urlStr) else {
            throw AEMETError.noData(envelope.descripcion ?? "Sin datos")
        }
        return url
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
}

// MARK: - Catalog

struct AemetMunicipio: Decodable, Identifiable {
    var id: String { codMunicipio }
    let codMunicipio: String
    let nombre: String
    let codProv: String?
    let nombreProv: String?

    enum CodingKeys: String, CodingKey {
        case codMunicipio = "id"
        case nombre
        case codProv
        case nombreProv
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
