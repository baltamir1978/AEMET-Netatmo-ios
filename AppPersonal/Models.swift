import Foundation

// MARK: - Flexible JSON decoder for Netatmo dashboardData

nonisolated struct AnyCodable: Decodable {
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

