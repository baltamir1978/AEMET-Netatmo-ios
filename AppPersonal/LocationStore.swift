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
        // `map { Self.migrate($0) }`, not `map(Self.migrate)`: handing a main-actor
        // function to `map` as a *value* is a data-race warning under the project's
        // default MainActor isolation, while calling it inside the closure runs it right
        // here, in `init`'s own context.
        let list = WidgetStore.loadLocations().map { Self.migrate($0) }
        locations = list
        selectedCode = WidgetStore.loadSelectedCode() ?? list.first?.code ?? ""
        resolvedCurrent = WidgetStore.loadResolvedCurrent().map { Self.migrate($0) }
        if let cur = resolvedCurrent { WidgetStore.saveResolvedCurrent(cur) }
        persist()
    }

    /// Bring a stored location up to date with the current rules — its timezone and its
    /// station/source label. Both are fields an older build wrote once and never revisits:
    /// a followed city with an `idema` already set never re-resolves its station, so
    /// without this an "Evc_Niembru-Llanes" (or a Canary location on peninsular time)
    /// would stay wrong forever. `shortStationName` is idempotent on its own output.
    private static func migrate(_ loc: SavedLocation) -> SavedLocation {
        var out = loc
        // Locations saved before the zone was resolved per territory all carry
        // "Europe/Madrid" — an hour off in the Canaries and in the Azores.
        out.tz = timeZone(for: loc)
        // Portuguese entries hold a *source* label there ("IPMA · Porto"), not a station
        // name. Recompute it rather than tidy it: the AEMET title-casing turned the
        // acronym into "Ipma", and it has to track the source the user picked anyway.
        if IPMA.isPortuguese(code: loc.code) {
            out.stationName = sourceLabel(for: loc)
            return out
        }
        guard let name = loc.stationName else { return loc }
        out.stationName = shortStationName(name)
        return out
    }

    func select(_ code: String) {
        guard code == SavedLocation.currentCode || locations.contains(where: { $0.code == code }) else { return }
        selectedCode = code
        // Only the selection changed, so save that alone and nudge the widgets *later*:
        // the Tiempo tab is a pager now, and reloading every timeline on each swipe burns
        // WidgetKit's daily reload budget for nothing — past it iOS starts ignoring
        // reloads and the widgets freeze. Nothing a widget shows depends on which page
        // you happen to be looking at, except the "follow the app" mode, and that can
        // wait until you settle.
        WidgetStore.saveSelectedCode(code)
        nudgeWidgets()
    }

    private var reloadTask: Task<Void, Never>?

    /// Reload widget timelines once things settle, cancelling any pending nudge. Use this
    /// instead of `WidgetCenter.reloadAllTimelines()` for anything the user can trigger
    /// repeatedly in a few seconds.
    func nudgeWidgets(after seconds: Double = 3) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
            self?.reloadTask = nil
        }
    }

    private var lastCurrentRefresh = Date.distantPast

    /// Re-resolve the GPS "Ubicación actual" entry for widgets even when the app shows a
    /// fixed city. That entry's `resolvedCurrent` is only refreshed in-app, so without
    /// this a widget set to "📍 Ubicación actual" freezes at the town GPS last resolved.
    /// Throttled; `resolveCurrent` reloads widget timelines on success. Returns whether it
    /// actually did the work, so a caller that only exists to keep the widget's copy fresh
    /// can stop right here instead of re-fetching a forecast on every city swipe.
    @discardableResult
    func refreshCurrentForWidgets() async -> Bool {
        guard selectedCode != SavedLocation.currentCode else { return false }   // already refreshed on-screen
        guard Date().timeIntervalSince(lastCurrentRefresh) > 10 * 60 else { return false }
        lastCurrentRefresh = Date()
        // Without a key there is no municipio catalog nor station network to resolve
        // against — Open-Meteo is queried straight from the coordinate.
        if AppConfiguration.shared.isAemetConfigured {
            return await resolveCurrent()
        }
        return await resolveCurrentBasic()
    }

    /// Fetch a GPS fix and resolve it to the AEMET municipio + observation station.
    @discardableResult
    func resolveCurrent() async -> Bool {
        guard let coord = try? await CurrentLocationService.shared.currentCoordinate() else { return false }
        // In Portugal there is no AEMET municipio to land on: resolving there used to snap
        // to the nearest *Spanish* town, so the tab quietly showed Badajoz's forecast while
        // you stood in Elvas. Hand the fix to IPMA instead.
        if let place = await resolvePortugueseCurrent(coord) { return place }
        if maestro.isEmpty {
            maestro = (try? await AEMETService.shared.allMunicipios()) ?? []
        }
        // El Goloso is a *district* of Madrid, not a municipio — its nearest municipio
        // *centroid* is Alcobendas (Madrid's centroid sits ~15 km south, downtown).
        // So we reverse-geocode to learn the real town name and match THAT to AEMET's
        // catalog; nearest-centroid is only the fallback when the geocoder is offline.
        let place = await reverseGeocode(coord)
        // Match the *municipio* name, never the displayed one: AEMET has no entry for a
        // parroquia or a city district, so matching "Posada" (or "Chamberí") finds nothing
        // and drops us into the nearest-centroid fallback this lookup exists to avoid.
        let municipio = place.city.flatMap { matchMunicipio(named: $0) }
            ?? nearestMunicipio(to: coord)
        guard let n = municipio else { return false }
        // Observation station (real readings, e.g. "Madrid, El Goloso") + a friendly label:
        // the one the user pinned for this municipio, else the nearest.
        let station = await station(forCode: n.codMunicipio, near: coord)
        // Show the *finest* real place we know; the station is surfaced separately as
        // context + its estimated distance.
        let realPlace = await placeName(place, at: coord, ine: n.codMunicipio) ?? n.nombre
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
                                tz: SavedLocation.timeZoneIdentifier(code: n.codMunicipio,
                                                                     lat: coord.latitude, lon: coord.longitude),
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
        nudgeWidgets()
        return true
    }

    /// Resolve the GPS "Ubicación actual" without any AEMET catalog (used by the Open-Meteo
    /// fallback when there is no AEMET key). Only needs the coordinate + a display name;
    /// Open-Meteo is queried by lat/lon, so there is no municipio or station to look up.
    @discardableResult
    func resolveCurrentBasic() async -> Bool {
        guard let coord = try? await CurrentLocationService.shared.currentCoordinate() else { return false }
        // IPMA needs no key either, so Portugal keeps its national service even here.
        if let place = await resolvePortugueseCurrent(coord) { return place }
        let city = await reverseGeocodeCity(coord)
        let loc = SavedLocation(code: SavedLocation.currentCode, name: city ?? "Ubicación actual",
                                province: nil, lat: coord.latitude, lon: coord.longitude, idema: nil,
                                tz: SavedLocation.timeZoneIdentifier(code: SavedLocation.currentCode,
                                                                     lat: coord.latitude, lon: coord.longitude))
        resolvedCurrent = loc
        WidgetStore.saveResolvedCurrent(loc)
        nudgeWidgets()
        return true
    }

    /// What one reverse-geocoding round-trip tells us about a coordinate.
    ///
    /// `city` and `displayName` are deliberately *not* the same thing. AEMET's catalog is
    /// keyed by municipio, so any lookup has to use the municipio name ("Llanes"); but the
    /// place you are actually standing in is often a smaller entity that owns no municipio
    /// of its own — a parroquia in Asturias, a district of a big city. Showing the municipio
    /// there reads as wrong ("Llanes" while you're in Posada de Llanes), so the UI takes
    /// the finer name and the catalog keeps the coarser one.
    private struct GeocodedPlace {
        /// Municipio/city as MapKit reports it: "Llanes", "Madrid".
        var city: String?
        /// District inside the city, when MapKit knows one: "Chamberí", "Fuencarral-El
        /// Pardo". Nil in towns with nothing below the municipio — including, sadly, every
        /// Asturian parroquia: the whole concejo of Llanes geocodes with `subLocality` nil,
        /// so Posada de Llanes cannot be told from Niembro here (only the postal code
        /// differs). Districts are a big-city affair.
        var subLocality: String?
        /// Street of the fix. Kept only to sanity-check `subLocality` — see `displayName`.
        var thoroughfare: String?
        var country: String?

        /// The name to put on screen: the district when there is a real one, else the town.
        var displayName: String? {
            guard let sub = subLocality, !sub.isEmpty else { return city }
            // MapKit sometimes repeats the town as its own sublocality; that's not detail.
            guard sub.caseInsensitiveCompare(city ?? "") != .orderedSame else { return city }
            // In towns with no districts the field gets filled with the *street* instead:
            // standing at the aqueduct in Segovia yields subLocality "Plaza del Azoguejo",
            // which as a location name is nonsense. A genuine district never matches the
            // street you're on ("Chamberí" vs "Cardenal Cisneros"), so that equality is a
            // reliable tell.
            guard sub.caseInsensitiveCompare(thoroughfare ?? "") != .orderedSame else { return city }
            // Portugal merged its parishes into "uniões de freguesias" that keep every old
            // name: downtown Porto geocodes to a 100-character list. A place name has to
            // fit a small widget, so anything enumerating names (commas) or longer than
            // the longest real city name we show ("Las Palmas de Gran Canaria") loses.
            guard !sub.contains(","), sub.count <= 28 else { return city }
            return sub
        }
    }

    /// The name to show for a fix: the finest real place we can put under it.
    ///
    /// Two sources, in this order, because each one covers what the other misses:
    /// MapKit knows the districts of big cities (Chamberí, Gràcia) and nothing below
    /// the municipio anywhere else; the bundled nomenclátor knows the villages and
    /// parroquias (Posada, Niembro) that own no municipio of their own. `ine` anchors
    /// the second lookup to the municipio AEMET already resolved.
    private func placeName(_ place: GeocodedPlace,
                           at coord: CLLocationCoordinate2D,
                           ine: String?) async -> String? {
        // A district from MapKit is more specific than any village lookup would be, and
        // it's the name a city dweller expects to read.
        if let display = place.displayName, display != place.city { return display }
        // Off the main actor: the first call parses ~29k rows, and this runs while the
        // location card is on screen.
        let nucleo = await Task.detached(priority: .userInitiated) {
            Nomenclator.nearest(to: coord, ine: ine)
        }.value
        return nucleo?.name ?? place.displayName
    }

    /// Reverse-geocode a coordinate to the name to display for it, Spanish locale.
    private func reverseGeocodeCity(_ coord: CLLocationCoordinate2D) async -> String? {
        let place = await reverseGeocode(coord)
        return await placeName(place, at: coord, ine: nil)
    }

    /// Town name, the finer place inside it, and the ISO country code — so a fix can be
    /// labelled and routed to the right national service off one geocoding round-trip.
    private func reverseGeocode(_ coord: CLLocationCoordinate2D) async -> GeocodedPlace {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let request = MKReverseGeocodingRequest(location: loc) else { return GeocodedPlace() }
        request.preferredLocale = Locale(identifier: "es_ES")
        let items = try? await request.mapItems
        guard let item = items?.first else { return GeocodedPlace() }
        // `placemark` is deprecated in iOS 26, but its replacement publishes neither the
        // country nor the sublocality: `MKAddressRepresentations` offers `cityName`,
        // `regionCode` (the region *within* a country) and a localized `fullAddress`
        // string. Routing a fix to the right national service deserves a stable ISO code,
        // and naming it deserves a real field — not substring matches on a translated
        // address — so we keep the deprecated accessor until Apple exposes both. (Nor is
        // there anywhere to retreat to: `CLGeocoder.reverseGeocodeLocation`, the classic
        // way to the same `CLPlacemark`, is deprecated in 26 too — pointing here.)
        // One access, so the build carries one warning instead of three; when Apple does
        // expose those fields, this line is the whole migration.
        let placemark = item.placemark
        return GeocodedPlace(city: item.addressRepresentations?.cityName,
                             subLocality: placemark.subLocality,
                             thoroughfare: placemark.thoroughfare,
                             country: placemark.isoCountryCode)
    }

    /// Resolve a GPS fix that landed in Portugal onto an IPMA-served location, and store
    /// it as the "Ubicación actual" entry. Returns nil when the fix isn't in Portugal, so
    /// the caller carries on with the AEMET path.
    ///
    /// The entry keeps the real town as its name and the IPMA `pt-` code of the forecast
    /// point it reads, which is what routes every later fetch to IPMA (or, further from a
    /// district capital, to Open-Meteo — the user's pick in the source sheet).
    private func resolvePortugueseCurrent(_ coord: CLLocationCoordinate2D) async -> Bool? {
        let place = await reverseGeocode(coord)
        guard place.country == "PT" else { return nil }
        guard let near = IPMA.nearest(to: coord.latitude, coord.longitude) else { return nil }
        var loc = SavedLocation(code: near.location.code, name: place.displayName ?? near.location.name,
                                province: nil, lat: coord.latitude, lon: coord.longitude,
                                idema: nil, tz: near.location.timeZone)
        loc.stationName = Self.sourceLabel(for: loc)
        loc.stationDistanceKm = IPMA.source(for: loc) == .ipma ? near.km : nil
        resolvedCurrent = loc
        WidgetStore.saveResolvedCurrent(loc)
        nudgeWidgets()
        return true
    }

    /// What the location card credits for a Portuguese location — the twin of the label
    /// the source sheet ticks.
    static func sourceLabel(for loc: SavedLocation) -> String? {
        guard IPMA.isPortuguese(code: loc.code) else { return nil }
        switch IPMA.source(for: loc) {
        case .ipma:      return IPMA.forecastPoint(for: loc).map { "IPMA · \($0.location.name)" }
        case .openMeteo: return "Open-Meteo"
        }
    }

    /// Refresh the stored source label/distance for a Portuguese location after the user
    /// switches service, so the card and the sheet agree straight away.
    func refreshPortugueseSource(forCode code: String) {
        func updated(_ loc: SavedLocation) -> SavedLocation {
            var out = loc
            out.stationName = Self.sourceLabel(for: loc)
            out.stationDistanceKm = IPMA.source(for: loc) == .ipma ? IPMA.forecastPoint(for: loc)?.km : nil
            return out
        }
        if let i = locations.firstIndex(where: { $0.code == code }) { locations[i] = updated(locations[i]) }
        if let cur = resolvedCurrent, cur.code == code {
            resolvedCurrent = updated(cur)
            WidgetStore.saveResolvedCurrent(resolvedCurrent!)
        }
        persist()
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
    ///
    /// AEMET's `ubi` field is raw operator data, and three of its habits leak into the UI:
    /// stations of the pollution-watch network carry an `EVC_` prefix ("EVC_NIEMBRU-LLANES",
    /// "EVC_DOÑANA"); municipio and site are often separated by a *double space* rather than
    /// a comma ("GIJÓN  MUSEL"); and a bare `.capitalized` shouts the linking words
    /// ("Cuevas De Felechosa"). The double space is normalised rather than split on, because
    /// AEMET also uses it inside plain place names ("SANTA EULALIA  DEL CAMPO") where
    /// splitting would leave "Del Campo".
    static func shortStationName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        if name.uppercased().hasPrefix("EVC_") { name = String(name.dropFirst(4)) }
        name = name.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let parts = name.components(separatedBy: CharacterSet(charactersIn: ",/"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let tail = parts.last else { return titleCased(name) }
        // A generic tail ("ALMERÍA/AEROPUERTO") says nothing on its own — keep the town.
        guard parts.count > 1, isGenericSite(tail) else { return titleCased(tail) }
        return titleCased(parts[0]) + ", " + titleCased(tail)
    }

    /// First words that describe a *kind* of place instead of naming one, so the qualifier
    /// before them has to stay ("Aeropuerto" alone could be any of AEMET's 20 of them).
    private static let genericSiteHeads: Set<String> = [
        "aeropuerto", "aerodromo", "base", "deposito", "depuradora", "embalse", "presa",
        "faro", "puerto", "parque", "instituto", "universidad", "facultad", "fac.",
        "jardin", "observatorio", "famet", "centro", "ciudad",
    ]

    private static func isGenericSite(_ tail: String) -> Bool {
        let head = tail.split(separator: " ").first.map(String.init) ?? tail
        return genericSiteHeads.contains(normalize(head))
    }

    /// Spanish title case: `.capitalized` first (it handles parentheses and initials like
    /// "S.E.A." correctly), then the linking words back down — except a leading one.
    private static func titleCased(_ s: String) -> String {
        let linking: Set<String> = ["de", "del", "la", "las", "los", "el", "y", "e", "en", "al", "a", "da", "do", "dels"]
        return s.capitalized.split(separator: " ").enumerated().map { i, word in
            i > 0 && linking.contains(normalize(String(word))) ? String(word).lowercased() : String(word)
        }.joined(separator: " ")
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
        guard !IPMA.isPortuguese(code: code) else { return nil }   // no AEMET network there
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

    /// Build the followed location for a search result. A Portuguese entry (`pt-` code)
    /// gets Lisbon time and its source label up front; a Spanish one resolves its
    /// observation station later, on the first load.
    func makeLocation(from m: AemetMunicipio) -> SavedLocation {
        var loc = SavedLocation(code: m.codMunicipio, name: m.nombre, province: nil,
                                lat: m.lat ?? selected.lat, lon: m.lon ?? selected.lon,
                                idema: nil)
        loc.tz = Self.timeZone(for: loc)
        if IPMA.isPortuguese(code: m.codMunicipio) { loc.stationName = Self.sourceLabel(for: loc) }
        return loc
    }

    /// Zone for a location, whichever country serves it: the IPMA catalogue knows its own
    /// (the Azores are an hour behind Lisboa), Spain resolves province-then-coordinate.
    static func timeZone(for loc: SavedLocation) -> String {
        if let pt = IPMA.location(forCode: loc.code) { return pt.timeZone }
        return SavedLocation.timeZoneIdentifier(code: loc.code, lat: loc.lat, lon: loc.lon)
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
        nudgeWidgets()
    }
}
