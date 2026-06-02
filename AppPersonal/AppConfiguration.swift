import Foundation
import Combine

/// All user-configurable settings. Stored in UserDefaults.
/// Sensitive tokens (access_token) are kept only in memory; the refresh_token is
/// stored in UserDefaults (acceptable for a personal app — use Keychain for prod).
class AppConfiguration: ObservableObject {
    static let shared = AppConfiguration()

    // MARK: - Netatmo credentials
    @Published var netatmoClientId: String      { didSet { ud.set(netatmoClientId,      forKey: "netatmo_client_id") } }
    @Published var netatmoClientSecret: String  { didSet { ud.set(netatmoClientSecret,  forKey: "netatmo_client_secret") } }
    @Published var netatmoRefreshToken: String  { didSet { ud.set(netatmoRefreshToken,  forKey: "netatmo_refresh_token") } }

    // MARK: - Station module IDs
    @Published var deviceId: String             { didSet { ud.set(deviceId,             forKey: "device_id") } }
    @Published var moduleExterior: String       { didSet { ud.set(moduleExterior,       forKey: "module_exterior") } }
    @Published var moduleRain: String           { didSet { ud.set(moduleRain,           forKey: "module_rain") } }
    @Published var stationLocation: String      { didSet { ud.set(stationLocation,      forKey: "station_location") } }

    // MARK: - Wind public station (optional)
    @Published var windStationId: String        { didSet { ud.set(windStationId,        forKey: "wind_station_id") } }
    @Published var windStationLoc: String       { didSet { ud.set(windStationLoc,       forKey: "wind_station_loc") } }
    @Published var windBboxNELat: String        { didSet { ud.set(windBboxNELat,        forKey: "wind_bbox_ne_lat") } }
    @Published var windBboxNELon: String        { didSet { ud.set(windBboxNELon,        forKey: "wind_bbox_ne_lon") } }
    @Published var windBboxSWLat: String        { didSet { ud.set(windBboxSWLat,        forKey: "wind_bbox_sw_lat") } }
    @Published var windBboxSWLon: String        { didSet { ud.set(windBboxSWLon,        forKey: "wind_bbox_sw_lon") } }

    // MARK: - AEMET
    @Published var aemetApiKey: String          { didSet { ud.set(aemetApiKey,          forKey: "aemet_api_key") } }

    // MARK: - Computed
    var isNetatmoConfigured: Bool {
        !deviceId.isEmpty && !netatmoClientId.isEmpty && !netatmoRefreshToken.isEmpty
    }
    var isAemetConfigured: Bool { !aemetApiKey.isEmpty }
    var windEnabled: Bool { !windStationId.isEmpty }

    var windBbox: (neLat: Double, neLon: Double, swLat: Double, swLon: Double)? {
        guard let a = Double(windBboxNELat), let b = Double(windBboxNELon),
              let c = Double(windBboxSWLat), let d = Double(windBboxSWLon) else { return nil }
        return (a, b, c, d)
    }

    // MARK: - Favorite stations: "city:FriendlyName,city2:Name2"
    @Published var favoriteNames: String        { didSet { ud.set(favoriteNames,        forKey: "favorite_names") } }

    /// Parsed favorites map: lowercased city → display name
    var favoriteCityNames: [String: String] {
        var map: [String: String] = [:]
        for raw in favoriteNames.split(separator: ",") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let colon = trimmed.firstIndex(of: ":") {
                let city = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let name = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                map[city] = name
            } else {
                map[trimmed.lowercased()] = trimmed
            }
        }
        return map
    }

    private let ud = UserDefaults.standard

    // MARK: - Defaults (sensitive values come from Secrets.swift, which is gitignored)
    private enum Defaults {
        static let clientId      = Secrets.netatmoClientId
        static let clientSecret  = Secrets.netatmoClientSecret
        static let refreshToken  = Secrets.netatmoRefreshToken
        static let deviceId      = Secrets.netatmoDeviceId
        static let moduleExt     = Secrets.netatmoModuleExt
        static let moduleRain    = Secrets.netatmoModuleRain
        static let stationLoc    = "La Granja de San Ildefonso · 1191 m"
        static let windId        = Secrets.netatmoWindId
        static let windLoc       = "Palazuelos de Eresma · 6 km"
        static let windNELat     = "40.88"
        static let windNELon     = "-3.98"
        static let windSWLat     = "40.82"
        static let windSWLon     = "-4.12"
        static let aemetKey      = Secrets.aemetApiKey
        static let favorites     = "Madrid:Madrid,Llanes:Nueva"
    }

    private init() {
        let ud = UserDefaults.standard
        func get(_ key: String, _ fallback: String) -> String { ud.string(forKey: key) ?? fallback }
        netatmoClientId     = get("netatmo_client_id",     Defaults.clientId)
        netatmoClientSecret = get("netatmo_client_secret", Defaults.clientSecret)
        netatmoRefreshToken = get("netatmo_refresh_token", Defaults.refreshToken)
        deviceId            = get("device_id",             Defaults.deviceId)
        moduleExterior      = get("module_exterior",       Defaults.moduleExt)
        moduleRain          = get("module_rain",           Defaults.moduleRain)
        stationLocation     = get("station_location",      Defaults.stationLoc)
        windStationId       = get("wind_station_id",       Defaults.windId)
        windStationLoc      = get("wind_station_loc",      Defaults.windLoc)
        windBboxNELat       = get("wind_bbox_ne_lat",      Defaults.windNELat)
        windBboxNELon       = get("wind_bbox_ne_lon",      Defaults.windNELon)
        windBboxSWLat       = get("wind_bbox_sw_lat",      Defaults.windSWLat)
        windBboxSWLon       = get("wind_bbox_sw_lon",      Defaults.windSWLon)
        aemetApiKey         = get("aemet_api_key",         Defaults.aemetKey)
        favoriteNames       = get("favorite_names",        Defaults.favorites)
    }
}
