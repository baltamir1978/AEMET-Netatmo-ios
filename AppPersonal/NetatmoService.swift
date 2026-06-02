import Foundation

/// Direct Netatmo API client with automatic OAuth2 token refresh.
actor NetatmoService {
    static let shared = NetatmoService()

    private let tokenURL   = URL(string: "https://api.netatmo.com/oauth2/token")!
    private let baseAPI    = "https://api.netatmo.com/api"
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    // MARK: - Decode helper (nonisolated so it runs outside actor isolation)

    nonisolated private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Token Management

    private func validAccessToken() async throws -> String {
        if let token = accessToken, Date() < tokenExpiry {
            return token
        }
        return try await refreshToken()
    }

    private func refreshToken() async throws -> String {
        // Read @MainActor-isolated config values on the main actor first
        let (clientId, clientSecret, currentRefreshToken) = await MainActor.run {
            let cfg = AppConfiguration.shared
            return (cfg.netatmoClientId, cfg.netatmoClientSecret, cfg.netatmoRefreshToken)
        }
        guard !clientId.isEmpty, !clientSecret.isEmpty, !currentRefreshToken.isEmpty else {
            throw NetatmoError.notConfigured
        }

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type":    "refresh_token",
            "client_id":     clientId,
            "client_secret": clientSecret,
            "refresh_token": currentRefreshToken,
        ]
        req.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try decode(TokenResponse.self, from: data)

        if let err = resp.error { throw NetatmoError.api(err) }

        accessToken = resp.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(resp.expiresIn ?? 10800) - 60)

        // Persist new refresh token
        if let newRefresh = resp.refreshToken {
            await MainActor.run { AppConfiguration.shared.netatmoRefreshToken = newRefresh }
        }
        return accessToken!
    }

    // MARK: - API calls

    func getStationsData(getFavorites: Bool = false) async throws -> StationsDataResponse {
        let token = try await validAccessToken()
        var comps = URLComponents(string: "\(baseAPI)/getstationsdata")!
        comps.queryItems = [
            URLQueryItem(name: "access_token",     value: token),
            URLQueryItem(name: "get_favorites",    value: getFavorites ? "true" : "false"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try decode(StationsDataResponse.self, from: data)
    }

    func getMeasure(deviceId: String, moduleId: String, scale: String, types: [String], dateBegin: Int) async throws -> GetMeasureResponse {
        let token = try await validAccessToken()
        var comps = URLComponents(string: "\(baseAPI)/getmeasure")!
        comps.queryItems = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "device_id",    value: deviceId),
            URLQueryItem(name: "module_id",    value: moduleId),
            URLQueryItem(name: "scale",        value: scale),
            URLQueryItem(name: "type",         value: types.joined(separator: ",")),
            URLQueryItem(name: "date_begin",   value: "\(dateBegin)"),
            URLQueryItem(name: "optimize",     value: "false"),
            URLQueryItem(name: "real_time",    value: "false"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try decode(GetMeasureResponse.self, from: data)
    }

    func getPublicData(neLat: Double, neLon: Double, swLat: Double, swLon: Double, requiredData: String = "wind") async throws -> PublicDataResponse {
        let token = try await validAccessToken()
        var comps = URLComponents(string: "\(baseAPI)/getpublicdata")!
        comps.queryItems = [
            URLQueryItem(name: "access_token",  value: token),
            URLQueryItem(name: "lat_ne",        value: String(neLat)),
            URLQueryItem(name: "lon_ne",        value: String(neLon)),
            URLQueryItem(name: "lat_sw",        value: String(swLat)),
            URLQueryItem(name: "lon_sw",        value: String(swLon)),
            URLQueryItem(name: "required_data", value: requiredData),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try decode(PublicDataResponse.self, from: data)
    }
}

// Models and errors defined in NetatmoModels.swift
