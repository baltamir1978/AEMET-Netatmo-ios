import Foundation
import WidgetKit
import SwiftUI

/// App Group shared between the AppPersonal app and its widget extension.
/// Mirrors the bundle id prefix (`Altamirano.AppPersonal`).
let appGroupID = "group.Altamirano.AppPersonal"

// MARK: - Widget deep links

/// URLs a widget tap opens in the app. The scheme needn't be registered in Info.plist:
/// WidgetKit already knows the widget belongs to this app and delivers the URL to
/// `onOpenURL`. The app maps each host onto the matching tab (and, for tides, scrolls to
/// the Mareas card inside Sol·Luna). Shared so the widgets and the app agree on the hosts.
enum WidgetDeepLink {
    static let scheme = "tiempoes"

    /// Widget → app-section hosts.
    static let aemet   = "aemet"    // Tiempo / AEMET tab
    static let netatmo = "netatmo"  // Actual tab
    static let tides   = "tides"    // Sol·Luna tab, scrolled to Mareas
    static let cosmos  = "cosmos"   // Sol·Luna tab

    static func url(_ host: String) -> URL { URL(string: "\(scheme)://\(host)")! }
}

// MARK: - Saved location

/// A location the user follows: AEMET forecast code + coordinates for sun/moon.
/// Shared by the AEMET tab, the Sol·Luna tab and both widgets.
struct SavedLocation: Codable, Identifiable, Equatable {
    var id: String { code }
    var code: String          // bare AEMET municipio code, e.g. "28079"
    var name: String
    var province: String?
    var lat: Double
    var lon: Double
    var idema: String?        // AEMET observation station (optional)
    var tz: String = "Europe/Madrid"
    /// Friendly observation-station name (only for the GPS "Ubicación actual" entry).
    var stationName: String? = nil
    /// Estimated km from the real GPS fix to that observation station (GPS entry only).
    var stationDistanceKm: Double? = nil

    /// Bridge to the sun/moon engine.
    var sunMoon: SunMoonLocation {
        SunMoonLocation(key: code, name: name, lat: lat, lon: lon, elevation: 0, tz: tz)
    }

    /// Sentinel for the GPS-driven "current location" entry.
    static let currentCode = "__current__"
    static let current = SavedLocation(code: currentCode, name: "Ubicación actual",
                                       province: nil, lat: 0, lon: 0, idema: nil)
    var isCurrent: Bool { code == Self.currentCode }

    static let defaults: [SavedLocation] = [
        SavedLocation(code: "40181", name: "La Granja",         province: "Segovia",  lat: 40.9000, lon: -4.0167, idema: "2465"),
        SavedLocation(code: "28079", name: "Madrid",            province: "Madrid",   lat: 40.4168, lon: -3.7038, idema: "3126Y"),
        SavedLocation(code: "33036", name: "Posada de Llanes",  province: "Asturias", lat: 43.4214, lon: -4.7546, idema: "1183X"),
    ]

    /// The zone a location's clock times belong to.
    ///
    /// `tz` used to default to `Europe/Madrid` for everything, which is wrong for the two
    /// bits of Spain that don't run on peninsular time: the Canaries are an hour behind,
    /// so every sunrise, moonrise and lunar phase there was printed an hour late.
    ///
    /// Province first (an AEMET code is an INE code, and 35/38 *are* the Canaries — no
    /// guessing), coordinate only as the fallback for entries that carry no municipio,
    /// like a GPS fix resolved without an AEMET key.
    nonisolated static func timeZoneIdentifier(code: String, lat: Double, lon: Double) -> String {
        if code.hasPrefix("35") || code.hasPrefix("38") { return "Atlantic/Canary" }
        if isCanaries(lat: lat, lon: lon) { return "Atlantic/Canary" }
        return "Europe/Madrid"
    }

    /// Bounding box of the archipelago, from El Hierro to Lanzarote, with a small margin.
    /// Madeira (32.6°N) and the Azores (west of 25°W) fall outside it on purpose — those
    /// are IPMA's and get their zone from the catalogue.
    nonisolated private static func isCanaries(lat: Double, lon: Double) -> Bool {
        (27.3...29.6).contains(lat) && (-18.4 ... -13.2).contains(lon)
    }
}

// MARK: - Refresh cadence

/// How often the app (background task) and the widgets try to pull fresh data.
/// Shared so the Settings picker, the widget timelines and the BG task all agree.
enum RefreshInterval: Int, CaseIterable, Identifiable {
    case h1 = 1, h3 = 3, h6 = 6, h12 = 12

    var id: Int { rawValue }
    var hours: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) * 3600 }
    var label: String { "\(rawValue) h" }

    static let `default` = RefreshInterval.h3

    /// The two choices surfaced in Settings. The full set of raw values stays valid
    /// (older builds / migrations), but the picker only offers a simple frequent/saver
    /// pair — the exact hour is more of a hint anyway (iOS throttles background work).
    static let pickerCases: [RefreshInterval] = [.h1, .h6]

    /// User-facing name for the simplified picker.
    var pickerLabel: String {
        switch self {
        case .h1: return "Frecuente · 1 h"
        case .h6: return "Ahorro · 6 h"
        default:  return label
        }
    }

    /// Collapse any stored cadence onto the closest simplified choice (for display).
    var simplified: RefreshInterval { hours <= 3 ? .h1 : .h6 }
}

// MARK: - Snapshots

/// Latest Netatmo reading, written by the app (Actual tab + background refresh).
/// The widget extension can't talk to Netatmo itself (OAuth lives in the app), so it
/// renders whatever the app last stored here.
///
/// Everything past `lon` was added for the dedicated Netatmo widget and is optional, so
/// snapshots written by older builds still decode (missing key → nil).
struct NetatmoSnapshot: Codable {
    var stationName: String
    var temperature: Double?   // °C, exterior
    var humidity: Double?      // %, exterior
    var pressure: Double?      // hPa
    var date: Date
    var lat: Double?           // station location — lets a widget show it only for its town
    var lon: Double?

    // Exterior extras
    var tempMinOut: Double?    // today's min at the station
    var tempMaxOut: Double?    // today's max
    var rain: Double?          // mm in the last hour
    var rainToday: Double?     // mm accumulated today

    // Interior (base station)
    var tempIn: Double?        // °C
    var humidityIn: Double?    // %
    var co2: Double?           // ppm
    var noise: Double?         // dB

    /// CO₂ comfort band, the way Netatmo colours it: ≤1000 good, ≤1600 fair, above that poor.
    var co2Level: Int? {
        guard let co2 else { return nil }
        return co2 <= 1000 ? 0 : (co2 <= 1600 ? 1 : 2)
    }
}

/// One hour of the AEMET hourly forecast, for the widget's hourly strip.
struct AemetHourPoint: Codable {
    var hour: Int          // 0…23
    var temp: Int          // °C
    var skyCode: String?   // AEMET sky code, drives the SF Symbol
    var prob: Int?         // precipitation probability %
    var isToday: Bool
}

/// One day of the AEMET daily forecast, for the widget's daily rows (Breezy-style).
struct AemetDayPoint: Codable {
    var date: Date
    var tempMin: Int?
    var tempMax: Int?
    var skyCode: String?
    var prob: Int?
}

/// Highest active AEMET weather warning for a location, shared by app + widgets.
/// `level`: 1 amarillo, 2 naranja, 3 rojo (verde means "no warning" and isn't stored).
struct AemetAlertBadge: Codable {
    var level: Int
    var phenomenon: String     // short label, e.g. "Tormentas"

    /// Banner/badge colour for the level.
    var color: Color {
        switch level {
        case 3:  return Color(red: 0.85, green: 0.18, blue: 0.18) // rojo
        case 2:  return Color(red: 0.95, green: 0.55, blue: 0.10) // naranja
        default: return Color(red: 0.95, green: 0.80, blue: 0.10) // amarillo
        }
    }

    var levelName: String {
        switch level {
        case 3:  return "rojo"
        case 2:  return "naranja"
        default: return "amarillo"
        }
    }
}

/// Latest AEMET forecast for the selected municipio, written by the AEMET tab.
struct AemetSnapshot: Codable {
    var municipio: String
    var tempMin: Int?
    var tempMax: Int?
    var currentTemp: Int?      // AEMET temp for the current hour (fallback for the big number)
    var skyDescription: String
    var skyCode: String?       // AEMET sky code, e.g. "11n" — drives the SF Symbol
    var date: Date
    // Optional so snapshots written by older app builds still decode.
    var hourly: [AemetHourPoint]?
    var daily: [AemetDayPoint]?
    var alert: AemetAlertBadge?    // highest active AEMET warning, if any
    // Station readings, so the widget's detail chips come from the same source as the
    // big number (they used to be Netatmo's, which is a different place entirely).
    var humidity: Int?             // %, from the observation station
    var windKmh: Int?              // km/h, from the observation station
}

// MARK: - Store

/// Read/write helpers over the App Group `UserDefaults` suite.
enum WidgetStore {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    private static let netatmoKey   = "widget.netatmo.snapshot"
    private static let aemetKey     = "widget.aemet.snapshot"
    private static let locationsKey = "widget.locations"
    private static let selectedKey  = "widget.locations.selected"
    private static let resolvedCurrentKey = "widget.locations.current"
    private static let intervalKey  = "widget.refresh.intervalHours"
    private static let aemetApiKeyKey = "widget.aemet.apiKey"
    private static let stationOverridesKey = "widget.stations.overrides"
    private static let lastRefreshKey = "widget.refresh.lastRun"

    // Refresh cadence ----------------------------------------------------------

    static func saveRefreshInterval(_ interval: RefreshInterval) {
        defaults?.set(interval.rawValue, forKey: intervalKey)
    }

    static func loadRefreshInterval() -> RefreshInterval {
        let raw = defaults?.integer(forKey: intervalKey) ?? 0
        return RefreshInterval(rawValue: raw) ?? .default
    }

    // AEMET key (mirrored from AppConfiguration so the widget can self-fetch) ---

    static func saveAemetApiKey(_ key: String) {
        defaults?.set(key, forKey: aemetApiKeyKey)
    }

    static func loadAemetApiKey() -> String? {
        let k = defaults?.string(forKey: aemetApiKeyKey)
        return (k?.isEmpty == false) ? k : nil
    }

    // Station overrides --------------------------------------------------------
    //
    // The observation station a location uses is normally the nearest one, but "nearest"
    // isn't always "most representative" — in the mountains a station 10 km away can sit
    // on the other side of the ridge while one 12 km away shares your valley and altitude.
    // When the user picks a station by hand we remember it *per municipio code*, because
    // the GPS "Ubicación actual" entry is rebuilt from scratch on every fix and would
    // otherwise snap straight back to the nearest station.

    private static func stationOverrides() -> [String: String] {
        defaults?.dictionary(forKey: stationOverridesKey) as? [String: String] ?? [:]
    }

    /// The station the user pinned for `code`, if any.
    static func stationOverride(forCode code: String) -> String? {
        stationOverrides()[code]
    }

    /// Pin `idema` as the station for `code`; pass nil to go back to automatic (nearest).
    static func saveStationOverride(_ idema: String?, forCode code: String) {
        var all = stationOverrides()
        all[code] = idema
        defaults?.set(all, forKey: stationOverridesKey)
    }

    // Snapshots ----------------------------------------------------------------

    static func save(netatmo snap: NetatmoSnapshot) {
        if let data = try? JSONEncoder().encode(snap) {
            defaults?.set(data, forKey: netatmoKey)
            reload()
        }
    }

    /// Pass `reloadWidgets: false` when the caller can fire repeatedly in a few seconds
    /// (the Tiempo tab's pager does) and will nudge the widgets itself once things settle.
    static func save(aemet snap: AemetSnapshot, reloadWidgets: Bool = true) {
        if let data = try? JSONEncoder().encode(snap) {
            defaults?.set(data, forKey: aemetKey)
            if reloadWidgets { reload() }
        }
    }

    /// Per-municipio snapshot so a widget configured for any followed city has data.
    static func save(aemet snap: AemetSnapshot, forCode code: String) {
        if let data = try? JSONEncoder().encode(snap) {
            defaults?.set(data, forKey: aemetKey + "." + code)
        }
    }

    static func loadNetatmo() -> NetatmoSnapshot? {
        guard let data = defaults?.data(forKey: netatmoKey) else { return nil }
        return try? JSONDecoder().decode(NetatmoSnapshot.self, from: data)
    }

    static func loadAemet() -> AemetSnapshot? {
        guard let data = defaults?.data(forKey: aemetKey) else { return nil }
        return try? JSONDecoder().decode(AemetSnapshot.self, from: data)
    }

    static func loadAemet(code: String) -> AemetSnapshot? {
        guard let data = defaults?.data(forKey: aemetKey + "." + code) else { return nil }
        return try? JSONDecoder().decode(AemetSnapshot.self, from: data)
    }

    // Locations ----------------------------------------------------------------

    static func saveLocations(_ list: [SavedLocation]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults?.set(data, forKey: locationsKey)
        }
    }

    static func loadLocations() -> [SavedLocation] {
        guard let data = defaults?.data(forKey: locationsKey),
              let list = try? JSONDecoder().decode([SavedLocation].self, from: data),
              !list.isEmpty else { return SavedLocation.defaults }
        return list
    }

    static func saveSelectedCode(_ code: String) {
        defaults?.set(code, forKey: selectedKey)
    }

    static func loadSelectedCode() -> String? {
        defaults?.string(forKey: selectedKey)
    }

    /// The GPS-resolved municipio for the "current location" entry.
    static func saveResolvedCurrent(_ loc: SavedLocation) {
        if let data = try? JSONEncoder().encode(loc) {
            defaults?.set(data, forKey: resolvedCurrentKey)
        }
    }

    static func loadResolvedCurrent() -> SavedLocation? {
        guard let data = defaults?.data(forKey: resolvedCurrentKey) else { return nil }
        return try? JSONDecoder().decode(SavedLocation.self, from: data)
    }

    /// The currently selected location, resolved against the saved list.
    static func selectedLocation() -> SavedLocation {
        let list = loadLocations()
        let code = loadSelectedCode()
        if code == SavedLocation.currentCode {
            return loadResolvedCurrent() ?? list.first ?? SavedLocation.defaults[0]
        }
        return list.first { $0.code == code } ?? list.first ?? SavedLocation.defaults[0]
    }

    // Refresh bookkeeping -------------------------------------------------------

    /// When the app (or its background task) last pulled everything the widgets show.
    static func lastRefresh() -> Date? {
        let t = defaults?.double(forKey: lastRefreshKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func markRefreshed() {
        defaults?.set(Date().timeIntervalSince1970, forKey: lastRefreshKey)
    }

    // --------------------------------------------------------------------------

    /// Nudge WidgetKit to rebuild timelines after the app refreshes its data.
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
