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

    // MARK: - AEMET
    @Published var aemetApiKey: String          { didSet { ud.set(aemetApiKey,          forKey: "aemet_api_key") } }

    /// True while `autoDetectStation()` is fetching modules from Netatmo.
    @Published var isDetectingStation = false
    /// Stations found in the account on the last detection (for the picker).
    @Published var availableStations: [DetectedStation] = []

    /// A Netatmo station discovered via `getStationsData`, ready to apply.
    struct DetectedStation: Identifiable, Hashable {
        let id: String          // main device id
        let name: String        // human-readable location / station name
        let moduleExterior: String
        let moduleRain: String
    }

    // MARK: - Computed
    var isNetatmoConfigured: Bool {
        !deviceId.isEmpty && !netatmoClientId.isEmpty && !netatmoRefreshToken.isEmpty
    }
    /// Credentials are enough to talk to Netatmo (modules can be auto-detected).
    var hasNetatmoCredentials: Bool {
        !netatmoClientId.isEmpty && !netatmoClientSecret.isEmpty && !netatmoRefreshToken.isEmpty
    }
    var isAemetConfigured: Bool { !aemetApiKey.isEmpty }

    // MARK: - Auto-detection

    /// Fills the station device + module IDs from the user's Netatmo account.
    /// Only the OAuth credentials are required; the IDs no longer need manual entry.
    @MainActor
    func autoDetectStation() async {
        guard hasNetatmoCredentials, !isDetectingStation else { return }
        isDetectingStation = true
        defer { isDetectingStation = false }
        do {
            let resp = try await NetatmoService.shared.getStationsData()
            let stations = (resp.body?.devices ?? []).map(Self.makeStation)
            availableStations = stations
            // Keep the user's current station if it still exists, else default to the first.
            if let chosen = stations.first(where: { $0.id == deviceId }) ?? stations.first {
                applyStation(chosen)
            }
        } catch {}
    }

    /// Switch the active station to one returned by the last detection.
    @MainActor
    func applyStation(_ station: DetectedStation) {
        deviceId        = station.id
        moduleExterior  = station.moduleExterior
        moduleRain      = station.moduleRain
        stationLocation = station.name
    }

    private static func makeStation(from device: NetatmoDevice) -> DetectedStation {
        var exterior = "", rain = ""
        for module in device.modules ?? [] {
            switch module.type {
            case "NAModule1": exterior = module.id   // outdoor temp/humidity
            case "NAModule3": rain = module.id        // rain gauge
            default: break
            }
        }
        let name: String
        if let place = device.place, let city = place.city {
            name = place.altitude.map { "\(city) · \($0) m" } ?? city
        } else {
            name = device.stationName ?? device.id
        }
        return DetectedStation(id: device.id, name: name, moduleExterior: exterior, moduleRain: rain)
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
        static let aemetKey      = Secrets.aemetApiKey
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
        aemetApiKey         = get("aemet_api_key",         Defaults.aemetKey)
    }
}
