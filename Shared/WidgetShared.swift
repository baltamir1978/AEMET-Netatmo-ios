import Foundation
import WidgetKit
import SwiftUI

/// App Group shared between the AppPersonal app and its widget extension.
/// Mirrors the bundle id prefix (`Altamirano.AppPersonal`).
let appGroupID = "group.Altamirano.AppPersonal"

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
}

// MARK: - Snapshots

/// Latest Netatmo exterior reading, written by the app's Actual tab.
struct NetatmoSnapshot: Codable {
    var stationName: String
    var temperature: Double?   // °C, exterior
    var humidity: Double?      // %, exterior
    var pressure: Double?      // hPa
    var date: Date
    var lat: Double?           // station location — lets a widget show it only for its town
    var lon: Double?
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

    // Snapshots ----------------------------------------------------------------

    static func save(netatmo snap: NetatmoSnapshot) {
        if let data = try? JSONEncoder().encode(snap) {
            defaults?.set(data, forKey: netatmoKey)
            reload()
        }
    }

    static func save(aemet snap: AemetSnapshot) {
        if let data = try? JSONEncoder().encode(snap) {
            defaults?.set(data, forKey: aemetKey)
            reload()
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

    // --------------------------------------------------------------------------

    /// Nudge WidgetKit to rebuild timelines after the app refreshes its data.
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
