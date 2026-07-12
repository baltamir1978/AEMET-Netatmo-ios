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
    private var stations: [AemetLiveStation] = []

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
        // Without a key there is no municipio catalog nor station network to resolve
        // against — Open-Meteo is queried straight from the coordinate.
        if AppConfiguration.shared.isAemetConfigured {
            _ = await resolveCurrent()
        } else {
            _ = await resolveCurrentBasic()
        }
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
        guard let n = municipio else { return false }
        // Observation station (real readings, e.g. "Madrid, El Goloso") + a friendly label:
        // the one the user pinned for this municipio, else the nearest. The station name
        // reliably yields "El Goloso"; the geocoded city is the fallback, then the municipio.
        let station = await station(forCode: n.codMunicipio, near: coord)
        // Show the *real* town as the primary name (geocoded city, else the municipio);
        // the station is surfaced separately as context + its estimated distance.
        let realPlace = cityName ?? n.nombre
        let stationName = station.map { Self.shortStationName($0.0.nombre) }
        let stationDist = station.map { distanceKm(coord, $0.1) }
        // Carry the GPS fix, not the municipio centroid (`n.lat/n.lon`): the station above
        // was picked from where you actually are, so anything that later measures from this
        // location — the station picker's list and distances, above all — has to measure
        // from the same point. With the centroid stored, the picker ranked stations from the
        // middle of the municipio and named a different "nearest" than the one in use.
        let loc = SavedLocation(code: n.codMunicipio, name: realPlace, province: nil,
                                lat: coord.latitude, lon: coord.longitude,
                                idema: station?.0.indicativo,
                                stationName: stationName, stationDistanceKm: stationDist)
        resolvedCurrent = loc
        WidgetStore.saveResolvedCurrent(loc)
        // If the same municipio is also a followed city, give it this station too. For AEMET
        // they are the same place (the pin is stored per municipio), and leaving them with
        // different `idema`s means the app reads a different station depending on whether
        // you're on "📍 Ubicación actual" or on the city — with each screen quoting whichever
        // of the two entries it happened to look up.
        if let (s, sCoord) = station, locations.contains(where: { $0.code == n.codMunicipio }) {
            apply(station: s, km: distanceKm(coord, sCoord), toCode: n.codMunicipio)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    /// Resolve the GPS "Ubicación actual" without any AEMET catalog (used by the Open-Meteo
    /// fallback when there is no AEMET key). Only needs the coordinate + a display name;
    /// Open-Meteo is queried by lat/lon, so there is no municipio or station to look up.
    @discardableResult
    func resolveCurrentBasic() async -> Bool {
        guard let coord = try? await CurrentLocationService.shared.currentCoordinate() else { return false }
        let city = await reverseGeocodeCity(coord)
        let loc = SavedLocation(code: SavedLocation.currentCode, name: city ?? "Ubicación actual",
                                province: nil, lat: coord.latitude, lon: coord.longitude, idema: nil)
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

    /// The live observation network, fetched once per session (24 h disk cache underneath).
    /// Only stations that publish live observations — the climatological inventory
    /// (`allStations`) also lists stations that never report hourly data (e.g. San Pablo
    /// de los Montes, 3298X → 404), which would leave humidity/wind blank.
    private func loadStations() async {
        if stations.isEmpty {
            stations = (try? await AEMETService.shared.observationStations()) ?? []
        }
    }

    /// The AEMET observation station nearest to `coord` (with its coordinate), if any.
    /// Ranks by the same great-circle km the picker lists, so "Automática" and the top of
    /// the picker's list are always the same station. (It used to rank by squared degrees,
    /// which stretches longitude — at 41°N that's ~25% off, enough to swap two stations
    /// sitting within half a kilometre of each other, like Segovia and El Paular.)
    private func nearestStation(to coord: CLLocationCoordinate2D) async -> (AemetLiveStation, CLLocationCoordinate2D)? {
        guard let best = await nearbyStations(to: coord, limit: 1).first?.station else { return nil }
        return (best, CLLocationCoordinate2D(latitude: best.lat, longitude: best.lon))
    }

    /// The station a location should use: the one pinned by the user for that municipio,
    /// otherwise the nearest. Everything that resolves a station goes through here, so a
    /// manual pick survives the GPS entry being rebuilt on every fix.
    private func station(forCode code: String, near coord: CLLocationCoordinate2D) async -> (AemetLiveStation, CLLocationCoordinate2D)? {
        await loadStations()
        if let pinned = WidgetStore.stationOverride(forCode: code),
           let s = stations.first(where: { $0.indicativo == pinned }) {
            return (s, CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon))
        }
        return await nearestStation(to: coord)
    }

    /// The observation stations closest to `coord`, nearest first, with their distance.
    /// Feeds the station picker: when several sit at a similar distance only the user knows
    /// which one actually shares their weather (same valley, same side of the sierra).
    /// A handful is enough — past the 4th the stations are too far to be representative.
    func nearbyStations(to coord: CLLocationCoordinate2D, limit: Int = 4) async -> [(station: AemetLiveStation, km: Double)] {
        await loadStations()
        return stations
            .map { (station: $0, km: distanceKm(coord, CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon))) }
            .sorted { $0.km < $1.km }
            .prefix(limit)
            .map { $0 }
    }

    /// Pin `station` as the observation station for `code` — or pass nil to go back to
    /// automatic (nearest). Updates the stored name/distance so the card, the widget
    /// snapshots and the next observation fetch all follow the new station.
    @discardableResult
    func selectStation(_ station: AemetLiveStation?, forCode code: String) async -> Bool {
        WidgetStore.saveStationOverride(station?.indicativo, forCode: code)
        guard let base = coordinate(forCode: code) else { return false }
        var chosen = station
        if chosen == nil { chosen = await nearestStation(to: base)?.0 }   // back to automatic
        guard let chosen else { return false }
        let km = distanceKm(base, CLLocationCoordinate2D(latitude: chosen.lat, longitude: chosen.lon))
        apply(station: chosen, km: km, toCode: code)
        return true
    }

    /// The station currently pinned for `code` (nil when it's resolved automatically).
    func pinnedStation(forCode code: String) -> String? {
        WidgetStore.stationOverride(forCode: code)
    }

    /// Name of the station the *selected* location is reading from — what the Tiempo tab's
    /// card shows. The picker quotes this instead of recomputing "nearest", so the two
    /// screens can't name different stations.
    ///
    /// The selected entry comes first on purpose: the GPS entry and a followed city can
    /// share a municipio code while being two different `SavedLocation` objects, so looking
    /// the code up in `locations` could answer with the followed city's station while the
    /// screen is showing the GPS one. That's exactly how the card said "El Paular" and the
    /// picker "Segovia".
    func stationName(forCode code: String) -> String? {
        if selected.code == code { return selected.stationName }
        let loc = locations.first { $0.code == code }
            ?? (resolvedCurrent?.code == code ? resolvedCurrent : nil)
        return loc?.stationName
    }

    /// Coordinates of a followed location — or of the resolved GPS entry, whose `code` is
    /// the municipio it landed on.
    func coordinate(forCode code: String) -> CLLocationCoordinate2D? {
        let loc = locations.first { $0.code == code }
            ?? (resolvedCurrent?.code == code ? resolvedCurrent : nil)
        return loc.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Write a station onto every entry that uses `code` (a followed city, the GPS entry,
    /// or both when GPS resolves to a town you also follow).
    private func apply(station: AemetLiveStation, km: Double, toCode code: String) {
        let name = Self.shortStationName(station.nombre)
        if let i = locations.firstIndex(where: { $0.code == code }) {
            locations[i].idema = station.indicativo
            locations[i].stationName = name
            locations[i].stationDistanceKm = km
        }
        if var cur = resolvedCurrent, cur.code == code {
            cur.idema = station.indicativo
            cur.stationName = name
            cur.stationDistanceKm = km
            resolvedCurrent = cur
            WidgetStore.saveResolvedCurrent(cur)
        }
        persist()
    }

    /// Great-circle distance between two coordinates, in kilometres.
    private func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
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

    /// Resolve and attach an AEMET observation station to a followed location that lacks
    /// one (e.g. added via search with `idema: nil`), so the AEMET tab can fetch live
    /// readings — humidity, wind, real current temperature — for it too. Honours a pinned
    /// station, else takes the nearest. Persists the enriched location and returns its
    /// `idema` (nil if none could be found).
    @discardableResult
    func attachNearestStation(toCode code: String) async -> String? {
        guard let idx = locations.firstIndex(where: { $0.code == code }) else { return nil }
        if let existing = locations[idx].idema { return existing }   // already resolved
        let loc = locations[idx]
        let coord = CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lon)
        guard let (station, stationCoord) = await station(forCode: code, near: coord) else { return nil }
        // The index may have shifted while we awaited the station catalog.
        guard locations.contains(where: { $0.code == code }) else { return nil }
        apply(station: station, km: distanceKm(coord, stationCoord), toCode: code)
        return station.indicativo
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
