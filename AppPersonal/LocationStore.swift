import Foundation
import Combine
import CoreLocation
import WidgetKit

/// Single source of truth for the locations the user follows and which one is
/// selected. Persists to the App Group so the widgets see the same data, and
/// reloads widget timelines on every change.
final class LocationStore: ObservableObject {
    static let shared = LocationStore()

    @Published private(set) var locations: [SavedLocation]
    @Published var selectedCode: String
    /// GPS-resolved municipio backing the "Ubicación actual" entry.
    @Published private(set) var resolvedCurrent: SavedLocation?

    private var maestro: [AemetMunicipio] = []
    private var stations: [AemetStation] = []

    /// Options shown in the location pickers: GPS entry first, then the saved list.
    var pickerOptions: [SavedLocation] { [SavedLocation.current] + locations }

    var selected: SavedLocation {
        if selectedCode == SavedLocation.currentCode {
            return resolvedCurrent ?? SavedLocation.current
        }
        return locations.first { $0.code == selectedCode }
            ?? locations.first
            ?? SavedLocation.defaults[0]
    }

    /// Label for the GPS entry in the picker.
    var currentDisplayName: String {
        resolvedCurrent.map { "📍 \($0.name)" } ?? "📍 Ubicación actual"
    }

    private init() {
        let list = WidgetStore.loadLocations()
        locations = list
        selectedCode = WidgetStore.loadSelectedCode() ?? list.first?.code ?? ""
        resolvedCurrent = WidgetStore.loadResolvedCurrent()
        persist()
    }

    func select(_ code: String) {
        guard code == SavedLocation.currentCode || locations.contains(where: { $0.code == code }) else { return }
        selectedCode = code
        persist()
    }

    /// Fetch a GPS fix and resolve it to the nearest AEMET municipio.
    @discardableResult
    func resolveCurrent() async -> Bool {
        guard let coord = try? await CurrentLocationService.shared.currentCoordinate() else { return false }
        if maestro.isEmpty {
            maestro = (try? await AEMETService.shared.allMunicipios()) ?? []
        }
        let withCoords = maestro.filter { $0.lat != nil && $0.lon != nil }
        let nearest = withCoords.min { a, b in
            sqDist(a, coord) < sqDist(b, coord)
        }
        guard let n = nearest, let lat = n.lat, let lon = n.lon else { return false }
        // The forecast is per-municipio, but the nearest observation station (e.g.
        // "Madrid, El Goloso") often sits closer and is what the Actual card reads.
        let idema = await nearestStationIdema(to: coord)
        let loc = SavedLocation(code: n.codMunicipio, name: n.nombre, province: nil,
                                lat: lat, lon: lon, idema: idema)
        resolvedCurrent = loc
        WidgetStore.saveResolvedCurrent(loc)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    /// The `indicativo` of the AEMET observation station nearest to `coord`, if any.
    private func nearestStationIdema(to coord: CLLocationCoordinate2D) async -> String? {
        if stations.isEmpty {
            stations = (try? await AEMETService.shared.allStations()) ?? []
        }
        let withCoords = stations.compactMap { st -> (AemetStation, Double, Double)? in
            guard let la = Self.sexagesimal(st.latitud), let lo = Self.sexagesimal(st.longitud) else { return nil }
            return (st, la, lo)
        }
        let nearest = withCoords.min { a, b in
            sqDist(lat: a.1, lon: a.2, c: coord) < sqDist(lat: b.1, lon: b.2, c: coord)
        }
        return nearest?.0.indicativo
    }

    private func sqDist(_ m: AemetMunicipio, _ c: CLLocationCoordinate2D) -> Double {
        sqDist(lat: m.lat ?? 0, lon: m.lon ?? 0, c: c)
    }

    private func sqDist(lat: Double, lon: Double, c: CLLocationCoordinate2D) -> Double {
        let dLat = lat - c.latitude
        let dLon = (lon - c.longitude) * cos(c.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    /// Parse AEMET's sexagesimal coordinate (e.g. "404431N" → 40.7419°). West/South negative.
    static func sexagesimal(_ raw: String?) -> Double? {
        guard let raw, let hemi = raw.last, hemi.isLetter else { return nil }
        let digits = raw.dropLast()
        guard digits.count >= 6, let value = Int(digits) else { return nil }
        let deg = Double(value / 10000)
        let min = Double((value / 100) % 100)
        let sec = Double(value % 100)
        let dec = deg + min / 60 + sec / 3600
        return (hemi == "S" || hemi == "W" || hemi == "O") ? -dec : dec
    }

    /// Add (or update) a location and select it.
    func add(_ loc: SavedLocation) {
        if let i = locations.firstIndex(where: { $0.code == loc.code }) {
            locations[i] = loc
        } else {
            locations.append(loc)
        }
        selectedCode = loc.code
        persist()
    }

    func remove(_ code: String) {
        guard locations.count > 1 else { return }   // keep at least one
        locations.removeAll { $0.code == code }
        if selectedCode == code { selectedCode = locations.first?.code ?? "" }
        persist()
    }

    private func persist() {
        WidgetStore.saveLocations(locations)
        WidgetStore.saveSelectedCode(selectedCode)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
