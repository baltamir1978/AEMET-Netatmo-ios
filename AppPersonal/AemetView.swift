import SwiftUI
import CoreLocation

/// The Tiempo tab: one **page per followed location**, side by side.
///
/// The tab owns the data and the networking; each page (`AemetCityView`) only draws the
/// `CityWeather` it is handed. Keeping a separate `CityWeather` per location is what makes
/// the paging honest — a page that slides in shows its own city's forecast from cache
/// straight away, instead of the previous city's numbers under the new city's name.
struct AemetView: View {
    @ObservedObject private var store = LocationStore.shared
    @State private var showManage = false
    @State private var searchText = ""
    @State private var searchResults: [AemetMunicipio] = []
    @State private var cachedMunicipios: [AemetMunicipio] = []
    @State private var showSearch = false
    @State private var searchDebounce: Task<Void, Never>? = nil
    /// Weather per page, keyed by the *picker* code — so the GPS entry (`__current__`)
    /// keeps its own copy even when it resolves to a town that is also followed.
    @State private var cities: [String: CityWeather] = [:]
    /// Pages already given a background load this session, so an uncached city isn't
    /// refetched every time the pager re-creates its page.
    @State private var preloaded: Set<String> = []

    /// Auto-refreshes (view appear, city switch) reuse cached AEMET data younger
    /// than this; only an explicit pull/tap forces a live request. Keeps us well
    /// under AEMET's request limits — forecasts only update a few times a day.
    private let aemetTTL: TimeInterval = 3 * 60 * 60
    /// Station readings publish hourly and only count as "now" for 2 h (`freshObsTemp`),
    /// so they get a much shorter TTL than the forecast: on the 3 h one, a 2½ h-old cached
    /// reading was thrown away as stale and the hero fell back to the forecast — while the
    /// widget, which refreshes observations every 30 min, showed the real station value.
    /// That's the two-degree gap between app and widget. Same window as the widget.
    private let aemetObsTTL: TimeInterval = 30 * 60
    /// Warnings are time-sensitive, so auto-refreshes accept fresher cache than the
    /// forecast. The CAP bundle is cached per CCAA, so cities sharing one reuse it.
    private let aemetAlertTTL: TimeInterval = 60 * 60

    private var locationName: String { store.selected.name }
    private var shortLocationName: String {
        locationName.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? locationName
    }
    private var locationIdema: String? { store.selected.idema }
    private var currentMunicipio: String { store.selected.code }
    /// Weather of the page on screen (drives the toolbar's spinner).
    private var selectedWeather: CityWeather { cities[store.selectedCode] ?? CityWeather() }

    /// Coordinates of the selected location (used for Open-Meteo air/pollen/UV).
    private var coords: (lat: Double, lon: Double)? {
        (store.selected.lat, store.selected.lon)
    }

    /// The location a page actually shows. The GPS entry in `pickerOptions` is a bare
    /// placeholder; the town it resolved to lives in `resolvedCurrent`.
    private func resolved(_ option: SavedLocation) -> SavedLocation {
        option.isCurrent ? (store.resolvedCurrent ?? option) : option
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Above the pages so it stays put while they slide, and on top of them so
                // its results dropdown isn't clipped by the pager.
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .zIndex(1)
                if store.pickerOptions.count > 1 { pageDots }
                pages
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // City switch + location manager live in one compact leading menu so the
            // trailing refresh + GPS buttons always fit (a crowded bar silently drops
            // trailing items on narrower screens / larger text). The menu is also the
            // way to reach a city that's several swipes away.
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Ubicación", selection: $store.selectedCode) {
                            ForEach(store.pickerOptions) { loc in
                                Text(loc.isCurrent ? store.currentDisplayName : loc.name).tag(loc.code)
                            }
                        }
                        Divider()
                        Button { showManage = true } label: {
                            Label("Gestionar ubicaciones", systemImage: "list.bullet")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(shortLocationName).fontWeight(.semibold)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedWeather.isLoading {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Button { Task { await loadForecast(force: true) } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Actualizar")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: geolocate) {
                        Image(systemName: "location")
                    }
                    .accessibilityLabel("Usar mi ubicación")
                }
            }
            .onChange(of: store.selectedCode) { _, newCode in
                store.select(newCode)
                searchText = ""
                Task { await loadForecast() }
                primeNeighbours()
            }
            .task {
                await loadForecast()
                primeNeighbours()
            }
            .sheet(isPresented: $showManage) {
                LocationManagerSheet { Task { await loadForecast() } }
            }
        }
    }

    // MARK: - Pages

    /// One page per followed location, swipeable. Each page primes itself from the disk
    /// cache as it appears, so it has something real to show before it finishes sliding in.
    private var pages: some View {
        TabView(selection: $store.selectedCode) {
            ForEach(store.pickerOptions) { option in
                AemetCityView(location: resolved(option),
                              data: cities[option.code] ?? CityWeather(),
                              onStationPicked: { stationChanged(on: option) },
                              onRefresh: { await loadForecast(force: true) })
                    .tag(option.code)
                    .onAppear { primeFromCache(option) }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// The user pinned a different observation station (or data source) for this page.
    /// Drop the old station's readings so the hero falls back to the forecast rather than
    /// showing the previous station's temperature while the new one loads.
    private func stationChanged(on option: SavedLocation) {
        update(option.code) { $0.obs = nil }
        let code = resolved(option).code
        if IPMA.isPortuguese(code: code) { store.refreshPortugueseSource(forCode: code) }
        Task { await loadForecast(force: true) }
    }

    /// Page control for the pager: a dot per location, the GPS entry marked with its arrow.
    /// Tappable to jump, and exposed to VoiceOver as one adjustable element (the standard
    /// page-control pattern) so swiping up/down moves between cities.
    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(store.pickerOptions) { option in
                let isOn = option.code == store.selectedCode
                Group {
                    if option.isCurrent {
                        Image(systemName: "location.fill").font(.system(size: 8))
                    } else {
                        Circle().frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(isOn ? AppTheme.green : Color.secondary.opacity(0.30))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { store.selectedCode = option.code }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ubicación")
        .accessibilityValue(Text(store.selected.name))
        .accessibilityHint("Desliza para cambiar de ubicación")
        .accessibilityAdjustableAction { direction in
            let options = store.pickerOptions
            guard let i = options.firstIndex(where: { $0.code == store.selectedCode }) else { return }
            let next = direction == .increment ? i + 1 : i - 1
            guard options.indices.contains(next) else { return }
            store.selectedCode = options[next].code
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Buscar municipio…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchText) { _, newVal in
                    if newVal.count < 2 { searchResults = []; showSearch = false; return }
                    searchDebounce?.cancel()
                    searchDebounce = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await performSearch(newVal)
                    }
                }
            if showSearch {
                VStack(spacing: 0) {
                    ForEach(searchResults) { result in
                        Button {
                            addLocation(result)
                        } label: {
                            HStack {
                                Text(result.nombre).fontWeight(.semibold).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(AppTheme.green)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        Divider()
                    }
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
        }
    }

    // MARK: - Search

    /// Add a searched municipio to the followed list and select it.
    private func addLocation(_ m: AemetMunicipio) {
        store.add(store.makeLocation(from: m))
        searchText = ""
        searchResults = []
        showSearch = false
        Task { await loadForecast() }
    }

    private func performSearch(_ query: String) async {
        if cachedMunicipios.isEmpty {
            cachedMunicipios = (try? await AEMETService.shared.allMunicipios()) ?? []
        }
        let q = query.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        searchResults = Array(
            (cachedMunicipios
                .filter { $0.nombre.lowercased().folding(options: .diacriticInsensitive, locale: .current).contains(q) }
             + IPMA.searchAsMunicipios(query))
                .prefix(10)
        )
        showSearch = !searchResults.isEmpty
    }

    // MARK: - Per-page state

    /// Mutate one page's weather in place.
    private func update(_ key: String, _ mutate: (inout CityWeather) -> Void) {
        var w = cities[key] ?? CityWeather()
        mutate(&w)
        cities[key] = w
    }

    /// Get the pages either side of the current one ready before they're needed.
    ///
    /// Their `onAppear` can't do this on its own: a paged `TabView` doesn't build a
    /// neighbouring page until the swipe is already under way, which for a location with
    /// no readable disk cache (Portugal, a city added minutes ago) means the page slides
    /// in empty and fills after you let go. Doing it here — on launch and on every
    /// selection change — means the next swipe in either direction lands on real data.
    private func primeNeighbours() {
        let options = store.pickerOptions
        guard let i = options.firstIndex(where: { $0.code == store.selectedCode }) else { return }
        for j in [i - 1, i + 1] where options.indices.contains(j) {
            primeFromCache(options[j])
        }
    }

    /// Give a page something to show the moment the pager brings it into view.
    ///
    /// First from the on-disk cache, synchronously — no network, no `await`, so the page
    /// paints as it slides in. Some locations have no cache to read that way: Portugal's
    /// lives behind an async IPMA load, and a city added minutes ago has none at all.
    /// Those get one background load instead, which still serves from disk when the disk
    /// is warm — so the page is ready before you let go of it either way.
    private func primeFromCache(_ option: SavedLocation) {
        guard cities[option.code]?.hasData != true else { return }
        let loc = resolved(option)
        guard loc.code != SavedLocation.currentCode else { return }   // GPS not resolved yet
        let cached = CityWeather.cached(for: loc)
        if cached.hasData {
            update(option.code) {
                $0.daily = cached.daily
                $0.hourly = cached.hourly
                $0.obs = cached.obs
                $0.loadedAt = cached.loadedAt
            }
            return
        }
        // Once per session per city: `onAppear` fires again every time the pager
        // re-creates the page, and an uncached city would refetch on each pass.
        guard !preloaded.contains(option.code) else { return }
        // The GPS page is the one thing never preloaded: filling it means taking a
        // location fix, which is the user's to ask for by opening that page.
        guard !option.isCurrent else { return }
        preloaded.insert(option.code)
        Task { await load(key: option.code) }
    }

    // MARK: - Networking

    /// Load the page currently on screen. Captured up front so a slow request started
    /// before a swipe writes its results onto the city it was asked about, not the one
    /// now on screen.
    private func loadForecast(force: Bool = false) async {
        await load(key: store.selectedCode, force: force)
    }

    private func load(key: String, force: Bool = false) async {
        // Portugal is IPMA's (or Open-Meteo's, per the source sheet), key or no key.
        if IPMA.isPortuguese(code: key)
            || (key == SavedLocation.currentCode
                && IPMA.isPortuguese(code: store.resolvedCurrent?.code ?? "")) {
            await loadPortugueseForecast(key: key, force: force)
            return
        }
        // No AEMET key → serve the whole forecast from the open Open-Meteo API instead.
        guard AppConfiguration.shared.isAemetConfigured else {
            await loadOpenMeteoForecast(key: key)
            return
        }
        // Auto-refreshes reuse fresh cache; pull/tap forces a live request.
        let maxAge: TimeInterval? = force ? nil : aemetTTL
        update(key) { $0.isLoading = true; $0.error = nil }
        // Resolve GPS → nearest municipio when the "current location" entry is active.
        if key == SavedLocation.currentCode {
            let ok = await store.resolveCurrent()
            if !ok && store.resolvedCurrent == nil {
                update(key) {
                    $0.error = String(localized: "No se pudo obtener tu ubicación. Revisa los permisos de localización.")
                    $0.isLoading = false
                }
                return
            }
            // GPS may have landed somewhere new; take whatever it cached for that town.
            primeFromCache(SavedLocation.current)
        } else if key == store.selectedCode {
            // The app is showing a fixed city, but a widget may be set to "📍 Ubicación
            // actual". That entry reads `resolvedCurrent`, which only this app refreshes —
            // so keep it (and its widget snapshot) fresh here too, or the widget freezes
            // at the town where GPS was last resolved. Only for the page on screen: a
            // background preload of a neighbouring page has no business taking a GPS fix.
            Task { await refreshCurrentLocationForWidget() }
        }
        let loc = resolved(store.pickerOptions.first { $0.code == key } ?? store.selected)
        let municipio = loc.code
        // A city added via search has no observation station yet (idema: nil), so it would
        // show no humidity/wind and no real current temperature. Resolve the nearest station
        // once (persisted), so this and every later load fetches live readings for it too.
        var idema = loc.idema
        if idema == nil, key != SavedLocation.currentCode {
            idema = await store.attachNearestStation(toCode: municipio)
        }

        // All calls run in parallel
        async let dResult = AEMETService.shared.forecastDaily(municipio: municipio, maxAge: maxAge)
        async let hResult = AEMETService.shared.forecastHourly(municipio: municipio, maxAge: maxAge)
        let obsTask = idema.map { id in
            Task<[AemetObservationRecord]?, Never> {
                try? await AEMETService.shared.observation(idema: id, maxAge: force ? nil : aemetObsTTL)
            }
        }
        let omTask = Task<OpenMeteoData?, Never> {
            await OpenMeteoService.shared.fetch(lat: loc.lat, lon: loc.lon)
        }
        let alertTask = Task<[AemetAlert], Never> {
            (try? await AEMETService.shared.alerts(
                municipioCode: municipio, lat: loc.lat, lon: loc.lon,
                maxAge: force ? nil : aemetAlertTTL)) ?? []
        }

        var newDaily: AemetDailyRoot? = nil
        var newHourly: AemetHourlyRoot? = nil
        var dailyErr: String? = nil
        var hourlyErr: String? = nil

        do { newDaily  = try await dResult  } catch { dailyErr  = error.localizedDescription }
        do { newHourly = try await hResult  } catch { hourlyErr = error.localizedDescription }
        let newObs = await obsTask?.value
        let newOM = await omTask.value
        let newAlerts = await alertTask.value

        update(key) { w in
            w.openMeteo = newOM ?? w.openMeteo
            w.alerts = newAlerts
            if newDaily != nil || newHourly != nil {
                w.daily  = newDaily  ?? w.daily
                w.hourly = newHourly ?? w.hourly
                w.obs    = newObs    ?? w.obs
                w.loadedAt = Date()
                w.error = nil
            } else if w.daily != nil || w.hourly != nil {
                w.error = String(localized: "AEMET sin respuesta · datos anteriores")
            } else {
                let detail = dailyErr ?? hourlyErr ?? String(localized: "sin respuesta")
                w.error = String(localized: "AEMET no disponible: \(detail)")
            }
            w.isLoading = false
        }
        if newDaily != nil || newHourly != nil {
            saveAemetSnapshot(key: key, location: loc)
            Task { await refreshAllWidgetCities() }
        }
    }

    /// Open-Meteo fallback used when there is no AEMET key. Fetches the open forecast and
    /// feeds the same `daily`/`hourly`/`obs` the views read, so the UI is provider-agnostic.
    private func loadOpenMeteoForecast(key: String) async {
        update(key) { $0.isLoading = true; $0.error = nil }
        // The current-location entry needs a GPS fix + name, but no AEMET catalog here.
        if key == SavedLocation.currentCode {
            _ = await store.resolveCurrentBasic()
            if store.resolvedCurrent == nil {
                update(key) {
                    $0.error = String(localized: "No se pudo obtener tu ubicación. Revisa los permisos de localización.")
                    $0.isLoading = false
                }
                return
            }
        }
        let loc = resolved(store.pickerOptions.first { $0.code == key } ?? store.selected)
        async let fcTask = OpenMeteoService.shared.fetchForecast(lat: loc.lat, lon: loc.lon)
        async let omTask = OpenMeteoService.shared.fetch(lat: loc.lat, lon: loc.lon)
        let forecast = await fcTask
        let om = await omTask
        update(key) { w in
            w.openMeteo = om ?? w.openMeteo
            if let f = forecast {
                w.daily = f.daily
                w.hourly = f.hourly
                w.obs = f.obs
                w.loadedAt = Date()
                w.error = nil
            } else if !w.hasData {
                w.error = String(localized: "No se pudo cargar la previsión (Open-Meteo).")
            }
            w.isLoading = false
        }
        if forecast != nil { saveAemetSnapshot(key: key, location: loc) }
    }

    /// Portugal. Feeds the same `daily`/`hourly`/`obs`/`alerts` from IPMA — or from
    /// Open-Meteo when the location sits far from a district capital and the source sheet
    /// says so. Warnings are IPMA's either way.
    private func loadPortugueseForecast(key: String, force: Bool) async {
        update(key) { $0.isLoading = true; $0.error = nil }
        if key == SavedLocation.currentCode {
            _ = await store.resolveCurrent()
            if store.resolvedCurrent == nil {
                update(key) {
                    $0.error = String(localized: "No se pudo obtener tu ubicación. Revisa los permisos de localización.")
                    $0.isLoading = false
                }
                return
            }
        }
        let loc = resolved(store.pickerOptions.first { $0.code == key } ?? store.selected)
        let maxAge: TimeInterval? = force ? nil : aemetTTL
        async let bundleTask = IPMAService.load(for: loc, maxAge: maxAge)
        // Air quality / pollen / UV are Open-Meteo's everywhere, Portugal included.
        async let omTask = OpenMeteoService.shared.fetch(lat: loc.lat, lon: loc.lon)
        let bundle = await bundleTask
        let om = await omTask
        update(key) { w in
            w.openMeteo = om ?? w.openMeteo
            if let bundle {
                w.daily = bundle.daily
                w.hourly = bundle.hourly
                w.obs = bundle.obs
                w.alerts = bundle.alerts
                w.loadedAt = Date()
                w.error = nil
            } else if !w.hasData {
                w.error = String(localized: "No se pudo cargar la previsión (IPMA).")
            }
            w.isLoading = false
        }
        if bundle != nil { saveAemetSnapshot(key: key, location: loc) }
    }

    /// Persist a city's AEMET forecast to the App Group (global key + keyed by code).
    private func saveAemetSnapshot(key: String, location loc: SavedLocation) {
        let w = cities[key] ?? CityWeather()
        let snap = AemetSnapshotBuilder.makeAemetSnapshot(municipio: loc.name, daily: w.daily, hourly: w.hourly,
                                          observation: w.obs, alert: w.alerts.first?.badge)
        // The global key is what a widget set to "follow the app" reads, so only the page
        // actually on screen may write it. Neither write reloads timelines here: a swipe
        // through four cities would fire four reloads, and WidgetKit's daily budget is
        // finite — `nudgeWidgets` coalesces them into one once the swiping stops.
        if key == store.selectedCode { WidgetStore.save(aemet: snap, reloadWidgets: false) }
        WidgetStore.save(aemet: snap, forCode: loc.code)
        store.nudgeWidgets()
    }

    // MARK: - Widget upkeep

    /// Re-resolve the GPS "Ubicación actual" entry and cache its forecast snapshot so a
    /// widget set to "📍 Ubicación actual" stays current even while the app shows a fixed
    /// city (otherwise `resolvedCurrent` freezes at the last town GPS resolved). Throttled.
    private func refreshCurrentLocationForWidget() async {
        // Its own 10-minute throttle. Without this early exit the forecast below would be
        // re-fetched on every city swipe just to rewrite an identical snapshot.
        guard await store.refreshCurrentForWidgets() else { return }
        // Make sure the resolved town has a forecast snapshot keyed by its code (cheap when
        // the disk cache is warm), so the "📍 Ubicación actual" weather widget has data and
        // doesn't fall back to the app's fixed city.
        guard let loc = store.resolvedCurrent, loc.code != currentMunicipio else { return }
        async let d = try? await AEMETService.shared.forecastDaily(municipio: loc.code, maxAge: aemetTTL)
        async let h = try? await AEMETService.shared.forecastHourly(municipio: loc.code, maxAge: aemetTTL)
        let (dr, hr) = await (d, h)
        guard dr != nil || hr != nil else { return }
        let cityAlert = (try? await AEMETService.shared.alerts(
            municipioCode: loc.code, lat: loc.lat, lon: loc.lon, maxAge: aemetAlertTTL))?.first?.badge
        var cityObs: [AemetObservationRecord]? = nil
        if let id = loc.idema { cityObs = try? await AEMETService.shared.observation(idema: id, maxAge: aemetObsTTL) }
        let snap = AemetSnapshotBuilder.makeAemetSnapshot(municipio: loc.name, daily: dr, hourly: hr,
                                                          observation: cityObs, alert: cityAlert)
        WidgetStore.save(aemet: snap, forCode: loc.code)
        store.nudgeWidgets()
    }

    /// Fetch & cache every followed city's forecast so a widget configured for any of
    /// them has data without the user opening that city. Throttled to ~20 min.
    private func refreshAllWidgetCities() async {
        let key = "widget.aemet.allCitiesRefreshedAt"
        let ud = UserDefaults.standard
        let last = ud.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 60 else { return }
        ud.set(Date(), forKey: key)

        for loc in store.locations where loc.code != currentMunicipio {
            if IPMA.isPortuguese(code: loc.code) {
                if let b = await IPMAService.load(for: loc, maxAge: aemetTTL) {
                    WidgetStore.save(aemet: AemetSnapshotBuilder.makeAemetSnapshot(
                        municipio: loc.name, daily: b.daily, hourly: b.hourly,
                        observation: b.obs, alert: b.alerts.first?.badge), forCode: loc.code)
                }
                continue
            }
            async let d = try? await AEMETService.shared.forecastDaily(municipio: loc.code, maxAge: aemetTTL)
            async let h = try? await AEMETService.shared.forecastHourly(municipio: loc.code, maxAge: aemetTTL)
            let (dr, hr) = await (d, h)
            guard dr != nil || hr != nil else { continue }
            let cityAlert = (try? await AEMETService.shared.alerts(
                municipioCode: loc.code, lat: loc.lat, lon: loc.lon, maxAge: aemetAlertTTL))?.first?.badge
            var cityObs: [AemetObservationRecord]? = nil
            if let id = loc.idema { cityObs = try? await AEMETService.shared.observation(idema: id, maxAge: aemetObsTTL) }
            let snap = AemetSnapshotBuilder.makeAemetSnapshot(municipio: loc.name, daily: dr, hourly: hr,
                                                              observation: cityObs, alert: cityAlert)
            WidgetStore.save(aemet: snap, forCode: loc.code)
        }
        store.nudgeWidgets()
    }

    /// Switch to the GPS "Ubicación actual" entry and load its forecast. `loadForecast`
    /// calls `store.resolveCurrent()`, which takes a real async GPS fix and reverse-geocodes
    /// it — the same path the widgets use. (The old code read `CLLocationManager.location`
    /// synchronously right after creating the manager, which is almost always nil before a
    /// fix lands, then fell back to the nearest *followed* city — hence it stuck on Madrid.)
    private func geolocate() {
        store.select(SavedLocation.currentCode)
        searchText = ""
        Task { await loadForecast() }
    }
}

// MARK: - Weather SF Symbol Icon

struct WeatherIconView: View {
    let code: String?

    private var category: String {
        guard let code else { return "unknown" }
        let isNight = code.hasSuffix("n")
        let n = Int(code.filter { $0.isNumber }) ?? 0
        switch n {
        case 11: return isNight ? "clear-n" : "clear"
        case 12, 13: return isNight ? "partly-n" : "partly"
        case 14, 15, 16: return "cloudy"
        case 17: return "high-clouds"
        case 23...26: return "rain"
        case 33...36: return "snow"
        case 43...46: return "shower"
        case 51...54: return "thunder"
        case 61...64: return "thunder-rain"
        case 71...74: return "light-snow"
        case 81: return "fog"
        case 82, 83: return "mist"
        default: return "unknown"
        }
    }

    private var sfSymbol: String {
        switch category {
        case "clear":         return "sun.max.fill"
        case "clear-n":       return "moon.stars.fill"
        case "partly":        return "cloud.sun.fill"
        case "partly-n":      return "cloud.moon.fill"
        case "cloudy":        return "cloud.fill"
        case "high-clouds":   return "smoke.fill"
        case "rain":          return "cloud.rain.fill"
        case "shower":        return "cloud.drizzle.fill"
        case "thunder":       return "cloud.bolt.fill"
        case "thunder-rain":  return "cloud.bolt.rain.fill"
        case "snow":          return "cloud.snow.fill"
        case "light-snow":    return "cloud.sleet.fill"
        case "fog":           return "cloud.fog.fill"
        case "mist":          return "cloud.fog"
        default:              return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch category {
        case "clear":                    return .yellow
        case "clear-n":                  return .indigo
        case "partly":                   return .orange
        case "partly-n":                 return .purple
        case "cloudy", "high-clouds":    return .gray
        case "rain", "shower":           return .blue
        case "thunder", "thunder-rain":  return .purple
        case "snow", "light-snow":       return .cyan
        case "fog", "mist":              return Color(.systemGray3)
        default:                         return .gray
        }
    }

    var body: some View {
        Image(systemName: sfSymbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(iconColor)
    }
}
