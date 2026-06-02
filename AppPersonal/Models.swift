import Foundation

// MARK: - Flexible JSON decoder for Netatmo dashboardData

struct AnyCodable: Decodable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Double.self)      { value = v }
        else if let v = try? c.decode(Int.self)    { value = Double(v) }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode(Bool.self)   { value = v }
        else                                       { value = nil }
    }

    var doubleValue: Double? { value as? Double }
    var intValue: Int?       { (value as? Double).map { Int($0) } }
    var stringValue: String? { value as? String }
}

// MARK: - Wind direction helper

func windDirection(_ angle: Int?) -> String {
    guard let angle else { return "—" }
    let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSO","SO","OSO","O","ONO","NO","NNO"]
    return dirs[Int((Double(angle) / 22.5).rounded()) % 16]
}

// MARK: - Tide (used by TidesService + CosmosView)

struct Tide: Identifiable {
    var id: String { time + type }
    let time: String
    let height: Double
    let type: String
}

// MARK: - AEMET preset locations

struct AemetLocation: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let idemaName: String
    let idema: String
}

let aemetPresetLocations: [AemetLocation] = [
    AemetLocation(key: "madrid",   name: "Madrid · Fuencarral-El Pardo", idemaName: "El Goloso", idema: "3126Y"),
    AemetLocation(key: "lagranja", name: "La Granja",                    idemaName: "Segovia",   idema: "2465"),
    AemetLocation(key: "llanes",   name: "Posada de Llanes",             idemaName: "Llanes",    idema: "1183X"),
]

let aemetPresetMunicipios: [String: String] = [
    "madrid":   "28079",
    "lagranja": "40181",
    "llanes":   "33036",
]
