import Foundation
import WidgetKit
import BackgroundTasks

/// Drives background data refresh for the app + widgets.
///
/// On every run it pulls fresh AEMET forecasts for each followed city (and the
/// GPS "current location"), updates the Netatmo reading, writes the shared
/// snapshots and reloads the widget timelines — then reschedules itself at the
/// cadence chosen in Ajustes (1/3/6/12 h). iOS ultimately decides when a
/// `BGAppRefreshTask` actually runs, so the widgets also self-fetch as a backup.
enum BackgroundRefresher {

    /// Must match the `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
    static let taskIdentifier = "Altamirano.AppPersonal.refresh"

    /// Ask iOS to run a refresh no sooner than the user's chosen interval.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppConfiguration.shared.refreshInterval.seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common in the simulator / when Background App Refresh is disabled.
            print("BGTaskScheduler submit failed: \(error)")
        }
    }

    /// Foreground twin of `refreshAll`, throttled: the widgets used to depend on the
    /// `BGAppRefreshTask` (which iOS defers for hours) or on the user happening to open the
    /// Actual tab, so opening the app and leaving left them showing the previous reading.
    /// Now every launch/foreground tops everything up, at most once every `minInterval`.
    static func refreshIfStale(minInterval: TimeInterval = 600) async {
        if let last = WidgetStore.lastRefresh(), Date().timeIntervalSince(last) < minInterval { return }
        await refreshAll()
    }

    /// Refresh everything the widgets show and write it to the App Group.
    @discardableResult
    static func refreshAll() async -> Bool {
        let store = LocationStore.shared
        var changed = false

        for loc in store.locations where !loc.isCurrent {
            if await refreshCity(loc) { changed = true }
        }

        // Keep the GPS "Ubicación actual" entry and its snapshot current.
        await store.refreshCurrentForWidgets()
        if let current = store.resolvedCurrent, await refreshCity(current) { changed = true }

        await refreshNetatmo()

        WidgetStore.markRefreshed()
        WidgetCenter.shared.reloadAllTimelines()
        return changed
    }

    /// Fetch a single municipio's forecast + warning and persist its snapshot.
    @discardableResult
    private static func refreshCity(_ loc: SavedLocation) async -> Bool {
        // No AEMET key → the app serves the whole forecast from Open-Meteo, so refresh
        // from there too. Otherwise a key-less install would never update its widgets in
        // the background (every AEMET call throws `notConfigured`).
        guard AppConfiguration.shared.isAemetConfigured else { return await refreshCityOpenMeteo(loc) }

        async let d = try? await AEMETService.shared.forecastDaily(municipio: loc.code)
        async let h = try? await AEMETService.shared.forecastHourly(municipio: loc.code)
        let (daily, hourly) = await (d, h)
        guard daily != nil || hourly != nil else { return false }

        let alert = (try? await AEMETService.shared.alerts(
            municipioCode: loc.code, lat: loc.lat, lon: loc.lon))?.first?.badge

        // The station reading is what makes the widget's big number the *real* current
        // temperature. Without it the snapshot falls back to the hourly forecast, so a
        // background run would quietly overwrite the app's observed temp with a predicted one.
        // Cities added via search start with `idema: nil` — resolve their station once here too.
        var idema = loc.idema
        if idema == nil, !loc.isCurrent {
            idema = await LocationStore.shared.attachNearestStation(toCode: loc.code)
        }
        var obs: [AemetObservationRecord]? = nil
        if let idema { obs = try? await AEMETService.shared.observation(idema: idema) }

        let snap = AemetSnapshotBuilder.makeAemetSnapshot(
            municipio: loc.name, daily: daily, hourly: hourly, observation: obs, alert: alert)
        store(snap, for: loc)
        return true
    }

    /// Open-Meteo twin of `refreshCity`, adapted into the same AEMET structs (so the
    /// snapshot — including the observed current temperature — is built exactly the same
    /// way). Open-Meteo has no warnings, so the badge stays whatever the app last stored.
    private static func refreshCityOpenMeteo(_ loc: SavedLocation) async -> Bool {
        guard let f = await OpenMeteoService.shared.fetchForecast(lat: loc.lat, lon: loc.lon) else { return false }
        let alert = WidgetStore.loadAemet(code: loc.code)?.alert
        let snap = AemetSnapshotBuilder.makeAemetSnapshot(
            municipio: loc.name, daily: f.daily, hourly: f.hourly, observation: f.obs, alert: alert)
        store(snap, for: loc)
        return true
    }

    /// Persist a city's snapshot, mirroring it into the global/legacy key when it's the
    /// city the app itself shows.
    private static func store(_ snap: AemetSnapshot, for loc: SavedLocation) {
        WidgetStore.save(aemet: snap, forCode: loc.code)
        let store = LocationStore.shared
        let isSelected = loc.code == store.selectedCode
            || (store.selectedCode == SavedLocation.currentCode && loc.code == store.resolvedCurrent?.code)
        if isSelected { WidgetStore.save(aemet: snap) }
    }

    /// Best-effort Netatmo exterior reading (temp / humidity / pressure).
    private static func refreshNetatmo() async {
        let cfg = AppConfiguration.shared
        guard cfg.isNetatmoConfigured,
              let resp = try? await NetatmoService.shared.getStationsData() else { return }
        let devices = resp.body?.devices ?? []
        guard let main = devices.first(where: { $0.id == cfg.deviceId }) ?? devices.first else { return }
        let mods = main.modules ?? []
        let exterior = mods.first(where: { $0.id == cfg.moduleExterior })
            ?? mods.first(where: { $0.type == "NAModule1" })
        let rain = mods.first(where: { $0.id == cfg.moduleRain })
            ?? mods.first(where: { $0.type == "NAModule3" })

        // The station physically lives in La Granja — tag the snapshot with its
        // coords so the weather widget shows it only when configured for that town.
        let st = LocationStore.shared.locations.first { $0.name.lowercased().contains("granja") }
            ?? SavedLocation.defaults[0]
        WidgetStore.save(netatmo: NetatmoSnapshotBuilder.make(
            station: main, exterior: exterior, rain: rain,
            name: cfg.stationLocation, lat: st.lat, lon: st.lon))
    }
}
