import Foundation

// MARK: - Errors

enum NetatmoError: LocalizedError {
    case notConfigured
    case api(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Credenciales de Netatmo no configuradas. Ve a Ajustes."
        case .api(let msg):  return "Error de Netatmo: \(msg)"
        }
    }
}

// MARK: - Token

nonisolated struct TokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let error: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken  = try c.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn    = try c.decodeIfPresent(Int.self,    forKey: .expiresIn)
        error        = try c.decodeIfPresent(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case error
    }
}

// MARK: - Stations data

nonisolated struct StationsDataResponse: Decodable {
    let body: StationsBody?
    let error: NetatmoAPIError?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body  = try c.decodeIfPresent(StationsBody.self,    forKey: .body)
        error = try c.decodeIfPresent(NetatmoAPIError.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey { case body, error }
}

nonisolated struct NetatmoAPIError: Decodable {
    let code: Int?
    let message: String?
}

nonisolated struct StationsBody: Decodable {
    let devices: [NetatmoDevice]
}

nonisolated struct NetatmoDevice: Decodable {
    let id: String
    let stationName: String?
    let reachable: Bool?
    let lastStatusStore: Int?
    let place: NetatmoPlace?
    let dashboardData: [String: AnyCodable]?
    let modules: [NetatmoModule]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case stationName = "station_name"
        case reachable
        case lastStatusStore = "last_status_store"
        case place
        case dashboardData = "dashboard_data"
        case modules
    }
}

nonisolated struct NetatmoModule: Decodable {
    let id: String
    let type: String?
    let dashboardData: [String: AnyCodable]?
    let reachable: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case dashboardData = "dashboard_data"
        case reachable
    }
}

nonisolated struct NetatmoPlace: Decodable {
    let city: String?
    let altitude: Int?
}

// MARK: - Measure

nonisolated struct GetMeasureResponse: Decodable {
    let body: [String: [Double?]]?
    let error: NetatmoAPIError?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body  = try c.decodeIfPresent([String: [Double?]].self, forKey: .body)
        error = try c.decodeIfPresent(NetatmoAPIError.self,     forKey: .error)
    }

    private enum CodingKeys: String, CodingKey { case body, error }
}

// MARK: - Public data

nonisolated struct PublicDataResponse: Decodable {
    let body: [PublicStation]?
    let error: NetatmoAPIError?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body  = try c.decodeIfPresent([PublicStation].self, forKey: .body)
        error = try c.decodeIfPresent(NetatmoAPIError.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey { case body, error }
}

nonisolated struct PublicStation: Decodable {
    let id: String
    let measures: [String: PublicMeasure]?
    let place: NetatmoPlace?
    let modules: [String]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case measures, place, modules
    }
}

nonisolated struct PublicMeasure: Decodable {
    let windStrength: Int?
    let windAngle: Int?
    let gustStrength: Int?
    let gustAngle: Int?
    let windTimeutc: Int?

    enum CodingKeys: String, CodingKey {
        case windStrength = "wind_strength"
        case windAngle    = "wind_angle"
        case gustStrength = "gust_strength"
        case gustAngle    = "gust_angle"
        case windTimeutc  = "wind_timeutc"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windStrength = try c.decodeIfPresent(Int.self, forKey: .windStrength)
        windAngle    = try c.decodeIfPresent(Int.self, forKey: .windAngle)
        gustStrength = try c.decodeIfPresent(Int.self, forKey: .gustStrength)
        gustAngle    = try c.decodeIfPresent(Int.self, forKey: .gustAngle)
        windTimeutc  = try c.decodeIfPresent(Int.self, forKey: .windTimeutc)
    }
}
