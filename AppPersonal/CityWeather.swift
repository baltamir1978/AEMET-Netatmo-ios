import Foundation

/// Everything the Tiempo tab shows for **one** location, kept apart from every other
/// location's copy.
///
/// The tab used to hold a single set of `daily`/`hourly`/`obs`/`alerts` and overwrite it
/// on each city switch, which meant the screen kept showing the *previous* city's forecast
/// (under the new city's name) until the network answered. With one of these per code, a
/// city you've already opened comes back instantly and correctly, and the page you're
/// swiping towards can render its own data while it slides in.
struct CityWeather {
    var daily: AemetDailyRoot?
    var hourly: AemetHourlyRoot?
    var obs: [AemetObservationRecord]?
    /// Air quality, pollen and UV — Open-Meteo's, everywhere.
    var openMeteo: OpenMeteoData?
    var alerts: [AemetAlert] = []
    /// When this data was fetched (or, when primed from disk, written). Drives the
    /// "Actualizado …" footer, so a cache-primed page doesn't claim to be current.
    var loadedAt: Date?
    var isLoading = false
    var error: String?

    var hasData: Bool { daily != nil || hourly != nil || obs != nil }

    /// The last good payload on disk for this location, with no network and no `await` —
    /// so a page can paint the moment it appears instead of flashing a spinner.
    ///
    /// AEMET only. Portugal's cache lives behind `IPMAService.load`, which is async and
    /// needs its own adaptation step; a Portuguese page fills in on its first fetch (which
    /// still reuses the same disk cache underneath) and stays in memory afterwards.
    static func cached(for loc: SavedLocation) -> CityWeather {
        guard !IPMA.isPortuguese(code: loc.code) else { return CityWeather() }
        var out = CityWeather()
        let d = AEMETService.shared.cachedDaily(municipio: loc.code)
        let h = AEMETService.shared.cachedHourly(municipio: loc.code)
        out.daily = d?.root
        out.hourly = h?.root
        if let id = loc.idema, let o = AEMETService.shared.cachedObservation(idema: id) {
            out.obs = o.records
        }
        // Oldest of the payloads on screen: the footer should quote the staler one rather
        // than flatter itself with the freshest.
        let ages = [d?.age, h?.age].compactMap { $0 }
        if let oldest = ages.max() { out.loadedAt = Date(timeIntervalSinceNow: -oldest) }
        return out
    }
}
