import Foundation
import Combine
import CoreLocation
import MapKit
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

    private var lastCurrentRefresh = Date.distantPast

    /// Re-resolve the GPS "Ubicación actual" entry for widgets even when the app shows a
    /// fixed city. That entry's `resolvedCurrent` is only refreshed in-app, so without
    /// this a widget set to "📍 Ubicación actual" freezes at the town GPS last resolved.
    /// Throttled; `resolveCurrent` reloads widget timelines on success.
    func refreshCurrentForWidgets() async {
        guard selectedCode != SavedLocation.currentCode else { return }   // already refreshed on-screen
        guard Date().timeIntervalSince(lastCurrentRefresh) > 10 * 60 else { return }
        lastCurrentRefresh = Date()
        _ = await resolveCurrent()
    }

    /// Fetch a GPS fix and resolve it to the AEMET municipio + observation station.
    @discardableResult
    func resolveCurrent() async -> Bool {
        guard let coord = try? await CurrentLocationService.shared.currentCoordinate() else { return false }
        if maestro.isEmpty {
            maestro = (try? await AEMETService.shared.allMunicipios()) ?? []
        }
        // El Goloso is a *district* of Madrid, not a municipio — its nearest municipio
        // *centroid* is Alcobendas (Madrid's centroid sits ~15 km south, downtown).
        // So we reverse-geocode to learn the real town name and match THAT to AEMET's
        // catalog; nearest-centroid is only the fallback when the geocoder is offline.
        let cityName = await reverseGeocodeCity(coord)
        let municipio = cityName.flatMap { matchMunicipio(named: $0) }
            ?? nearestMunicipio(to: coord)
        guard let n = municipio, let lat = n.lat, let lon = n.lon else { return false }
        // Nearest observation station (real readings, e.g. "Madrid, El Goloso") + a
        // friendly label. The station name reliably yields "El Goloso"; the geocoded
        // city is the fallback, then the municipio.
        let station = await nearestStation(to: coord)
        let displayName = station.map { Self.shortStationName($0.nombre) }
            ?? cityName
            ?? n.nombre
        let loc = SavedLocation(code: n.codMunicipio, name: displayName, province: nil,
                                lat: lat, lon: lon, idema: station?.indicativo)
        resolvedCurrent = loc
        WidgetStore.saveResolvedCurrent(loc)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    /// Reverse-geocode a coordinate to its city/town name (e.g. "Madrid"), Spanish locale.
    /// Uses MapKit's MKReverseGeocodingRequest (CLGeocoder is deprecated since iOS 26).
    private func reverseGeocodeCity(_ coord: CLLocationCoordinate2D) async -> String? {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let request = MKReverseGeocodingRequest(location: loc) else { return nil }
        request.preferredLocale = Locale(identifier: "es_ES")
        let items = try? await request.mapItems
        return items?.first?.addressRepresentations?.cityName
    }

    /// The AEMET municipio whose centroid is closest to `coord` (fallback resolution).
    private func nearestMunicipio(to coord: CLLocationCoordinate2D) -> AemetMunicipio? {
        maestro.filter { $0.lat != nil && $0.lon != nil }
            .min { sqDist($0, coord) < sqDist($1, coord) }
    }

    /// The AEMET municipio whose name matches `name` (accent/case-insensitive), if any.
    private func matchMunicipio(named name: String) -> AemetMunicipio? {
        let target = Self.normalize(name)
        return maestro.first { Self.normalize($0.nombre) == target && $0.lat != nil }
    }

    /// The AEMET observation station nearest to `coord`, if any.
    private func nearestStation(to coord: CLLocationCoordinate2D) async -> AemetStation? {
        if stations.isEmpty {
            stations = (try? await AEMETService.shared.allStations()) ?? []
        }
        let withCoords = stations.compactMap { st -> (AemetStation, Double, Double)? in
            guard let la = Self.sexagesimal(st.latitud), let lo = Self.sexagesimal(st.longitud) else { return nil }
            return (st, la, lo)
        }
        return withCoords.min { sqDist(lat: $0.1, lon: $0.2, c: coord) < sqDist(lat: $1.1, lon: $1.2, c: coord) }?.0
    }

    /// "MADRID, EL GOLOSO" → "El Goloso"; "MADRID/RETIRO" → "Retiro". Drops the leading
    /// province/town qualifier and title-cases the friendly remainder.
    static func shortStationName(_ raw: String) -> String {
        let tail = raw.split(whereSeparator: { $0 == "," || $0 == "/" }).last.map(String.init) ?? raw
        return tail.trimmingCharacters(in: .whitespaces).capitalized
    }

    /// Lowercased, accent-stripped form for tolerant name matching.
    static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
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
