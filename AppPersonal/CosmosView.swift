import SwiftUI

struct CosmosView: View {
    @State private var selectedDate = Date()
    @ObservedObject private var store = LocationStore.shared
    @AppStorage("tide_station_id") private var selectedTideStationId = "4"
    @State private var sunMoon: SunMoonResult?
    @State private var moonPhases: [MoonPhaseEvent]?
    @State private var tidesPair: TidesDayPair?
    @State private var astroEvents: [AstroEvent]?
    @State private var isLoading = false
    // Mini-calendar for the moon phases beyond the first few rows.
    @State private var moonCalMonth = Date()
    @State private var selectedMoonDay: Date?

    /// Spanish, Monday-first calendar used by the moon mini-calendar.
    private var esCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_ES")
        c.firstWeekday = 2
        return c
    }

    private var dateISO: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: selectedDate)
    }

    /// The day the Sun·Moon card reflects: a tapped calendar day if any, else the picker date.
    private var activeDay: Date { selectedMoonDay ?? selectedDate }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if isLoading { ProgressView().padding(6) }
                    if let sm = sunMoon { sunMoonCard(sm) }
                    if moonPhases?.isEmpty == false || astroEvents?.isEmpty == false {
                        moonCalendarCard(moonPhases ?? [])
                    }
                    if let t = tidesPair { tidesCard(t) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .navigationTitle("Sol · Luna")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 6) {
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: selectedDate) { _, _ in Task { await loadAll() } }
                        if !Calendar.current.isDateInToday(selectedDate) {
                            Button("Hoy") {
                                selectedDate = Date()
                                Task { await loadAll() }
                            }
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(AppTheme.green).foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().scaleEffect(0.75) }
                        Picker("", selection: $store.selectedCode) {
                            ForEach(store.pickerOptions) { loc in
                                Text(loc.isCurrent ? store.currentDisplayName : loc.name).tag(loc.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: store.selectedCode) { _, newCode in
                            store.select(newCode)
                            Task { await refreshLocationAndSun() }
                        }
                    }
                }
            }
            .task { await loadAll() }
            .refreshable { await loadAll() }
        }
    }

    // MARK: - Sun/Moon card

    private func sunMoonCard(_ data: SunMoonResult) -> some View {
        VStack(spacing: 0) {
            // Date this card reflects (follows the picker or a tapped calendar day).
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption2).foregroundStyle(AppTheme.green)
                Text(formatEventDate(activeDay))
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
            Divider()
            // Sun row: 4 columns
            HStack(spacing: 0) {
                sunCell("🌅", data.sun.sunrise  ?? "—", "Amanecer")
                Divider().frame(maxHeight: 58)
                sunCell("☀️", data.sun.noon     ?? "—", "Mediodía")
                Divider().frame(maxHeight: 58)
                sunCell("🌇", data.sun.sunset   ?? "—", "Atardecer")
                Divider().frame(maxHeight: 58)
                sunCell("⏱", data.sun.daylight ?? "—", "Duración")
            }
            Divider()
            // Moon row
            HStack(spacing: 12) {
                Text(data.moon.emoji).font(.system(size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.moon.phase).font(.subheadline).fontWeight(.semibold)
                    Text("Iluminación \(Int((data.moon.illumination * 100).rounded()))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let rise = data.moon.moonrise {
                        Text("Salida \(rise)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let set = data.moon.moonset {
                        Text("Puesta \(set)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.05))
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func sunCell(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(icon).font(.title3)
            Text(value).font(.subheadline).fontWeight(.bold).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: - Moon phase detail row

    private func moonPhaseRow(_ phase: MoonPhaseEvent) -> some View {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: phase.datetime)).day ?? 0
        let relative: String
        switch days {
        case 0:  relative = "Hoy"
        case 1:  relative = "Mañana"
        default: relative = "En \(days) días"
        }
        // Alternate row tint by phase kind (like the tides list): new = cool, full = warm.
        let kindColor = phase.kind == .new
            ? Color(red: 0.93, green: 0.94, blue: 0.99)
            : Color(red: 1.0, green: 0.98, blue: 0.88)
        return HStack(spacing: 12) {
            Text(phase.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.label).font(.subheadline).fontWeight(.bold)
                Text(relative).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatEventDate(phase.datetime)).font(.caption).foregroundStyle(.secondary)
                Text(phase.timeLocal).font(.subheadline).fontWeight(.bold).monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(days == 0 ? AppTheme.greenSoft : kindColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(days == 0 ? AppTheme.green.opacity(0.4) : Color.clear))
    }

    // MARK: - Moon mini-calendar

    private func moonCalendarCard(_ phases: [MoonPhaseEvent]) -> some View {
        // Moon phases and astronomical events landing on each day of the shown month.
        let moonByDay = Dictionary(phases.map { (esCal.startOfDay(for: $0.datetime), $0) },
                                   uniquingKeysWith: { a, _ in a })
        let astroByDay = Dictionary(grouping: astroEvents ?? [],
                                    by: { esCal.startOfDay(for: $0.datetime) })
        let minMonth = startOfMonth(selectedDate)
        let canGoBack = moonCalMonth > minMonth

        return VStack(spacing: 0) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack).opacity(canGoBack ? 1 : 0.3)
                Spacer()
                Text(monthTitle(moonCalMonth))
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()

            HStack(spacing: 0) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { d in
                    Text(d).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 10).padding(.top, 8)

            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(monthCells().enumerated()), id: \.offset) { _, day in
                    if let day {
                        let key = esCal.startOfDay(for: day)
                        moonDayCell(day, phase: moonByDay[key], astro: astroByDay[key] ?? [])
                    } else { Color.clear.frame(height: 38) }
                }
            }
            .padding(10)

            if let sel = selectedMoonDay {
                let key = esCal.startOfDay(for: sel)
                let moon = moonByDay[key]
                let evs = astroByDay[key] ?? []
                if moon != nil || !evs.isEmpty {
                    Divider()
                    VStack(spacing: 6) {
                        if let moon { moonPhaseRow(moon) }
                        ForEach(evs) { astroRow($0) }
                    }
                    .padding(10)
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func moonDayCell(_ day: Date, phase: MoonPhaseEvent?, astro: [AstroEvent]) -> some View {
        let isToday = esCal.isDateInToday(day)
        let isSelected = selectedMoonDay.map { esCal.isDate($0, inSameDayAs: day) } ?? false
        let hasEvent = phase != nil || !astro.isEmpty
        // Moon emoji takes the cell; an astro-only day shows its own emoji.
        let emoji = phase?.emoji ?? astro.first?.emoji ?? " "
        let tint: Color
        if let phase {
            tint = phase.kind == .new ? Color(red: 0.93, green: 0.94, blue: 0.99)
                                       : Color(red: 1.0, green: 0.98, blue: 0.88)
        } else if !astro.isEmpty {
            tint = AppTheme.greenSoft
        } else {
            tint = .clear
        }
        return VStack(spacing: 1) {
            Text("\(esCal.component(.day, from: day))")
                .font(.caption).fontWeight(hasEvent ? .bold : .regular)
                .foregroundStyle(hasEvent ? .primary : .secondary)
            Text(emoji).font(.caption2)
        }
        .frame(maxWidth: .infinity).frame(height: 38)
        .background(isSelected ? AppTheme.greenSoft : tint)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // Dot hint when an astro event is hidden behind a moon emoji.
        .overlay(alignment: .topTrailing) {
            if phase != nil && !astro.isEmpty {
                Circle().fill(AppTheme.green).frame(width: 5, height: 5).padding(3)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(isSelected ? AppTheme.green : (isToday ? AppTheme.green.opacity(0.4) : .clear),
                    lineWidth: isSelected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping any day re-points the Sun·Moon card to it; days with events also
            // toggle the detail panel below.
            selectedMoonDay = isSelected ? nil : day
            loadSunMoon()
        }
    }

    private func changeMonth(_ delta: Int) {
        if let m = esCal.date(byAdding: .month, value: delta, to: moonCalMonth) {
            moonCalMonth = startOfMonth(m)
        }
    }

    /// Leading blanks (nil) + each day of `moonCalMonth`, aligned to a Monday-first week.
    private func monthCells() -> [Date?] {
        guard let range = esCal.range(of: .day, in: .month, for: moonCalMonth) else { return [] }
        let weekday = esCal.component(.weekday, from: moonCalMonth)   // 1=Sun … 7=Sat
        let lead = (weekday - esCal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            cells.append(esCal.date(byAdding: .day, value: d - 1, to: moonCalMonth))
        }
        return cells
    }

    private func startOfMonth(_ date: Date) -> Date {
        esCal.date(from: esCal.dateComponents([.year, .month], from: date)) ?? date
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date).capitalized
    }

    // MARK: - Tides card

    private func tidesCard(_ pair: TidesDayPair) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mareas")
                    .font(.caption).fontWeight(.bold).textCase(.uppercase)
                    .foregroundStyle(.secondary).tracking(1)
                Spacer()
                Picker("", selection: $selectedTideStationId) {
                    ForEach(ihmStations) { st in
                        Text(st.name).tag(st.id)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .onChange(of: selectedTideStationId) { _, _ in
                    tidesPair = nil
                    Task { await loadTides() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ForEach(pair.days) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatTideDay(day.date))
                        .font(.caption).fontWeight(.bold).textCase(.uppercase)
                        .foregroundStyle(.secondary).tracking(1)
                        .padding(.horizontal, 16).padding(.top, 10)
                    if day.tides.isEmpty {
                        Text("Sin datos").font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    } else {
                        ForEach(day.tides) { tide in tideRow(tide) }
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func tideRow(_ tide: Tide) -> some View {
        HStack(spacing: 10) {
            Text(tide.type == "pleamar" ? "🌊" : "🏖️").font(.body)
            Text(tide.type == "pleamar" ? "Pleamar" : "Bajamar")
                .font(.subheadline).fontWeight(.semibold)
            Spacer()
            Text(tide.time).font(.subheadline).foregroundStyle(.secondary)
            Text(String(format: "%.2f m", tide.height)).font(.subheadline).fontWeight(.bold)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(tide.type == "pleamar" ? Color(red: 0.94, green: 0.97, blue: 1.0)
                                           : Color(red: 1.0, green: 0.98, blue: 0.88))
        .padding(.horizontal, 12)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Astro event detail row

    private func astroRow(_ event: AstroEvent) -> some View {
        let isToday = event.date == dateISO
        let soon = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let isSoon = event.datetime <= soon
        return HStack(spacing: 10) {
            Text(event.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.label).font(.subheadline).fontWeight(.bold)
                if let details = event.details {
                    Text(details).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatEventDate(event.datetime)).font(.caption).foregroundStyle(.secondary)
                Text(event.timeLocal).font(.subheadline).fontWeight(.bold)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isToday ? Color(red: 1.0, green: 0.95, blue: 0.75)
                             : isSoon ? AppTheme.greenSoft
                             : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isToday ? Color.yellow : isSoon ? AppTheme.green.opacity(0.35) : Color.clear))
    }

    // MARK: - Helpers

    private func formatTideDay(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        guard let date = f.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "EEEE d MMM"
        return df.string(from: date).capitalized
    }

    private func formatEventDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "EEE d MMM yyyy"
        return df.string(from: date)
    }

    // MARK: - Data loading

    private func loadAll() async {
        // Astronomy is deterministic and offline — compute it first (before any await)
        // so the Sun·Moon card and calendar paint instantly using the known location,
        // never waiting on GPS resolution or the tides network call.
        // loadMoonPhases clears selectedMoonDay so the Sun·Moon card resolves to the
        // picker date, not a stale tapped day.
        loadMoonPhases()
        loadAstroEvents()
        loadSunMoon()
        isLoading = true
        // Refine the GPS-backed location, then recompute the location-dependent pieces.
        if store.selectedCode == SavedLocation.currentCode {
            _ = await store.resolveCurrent()
            loadSunMoon()
            loadAstroEvents()
        }
        await loadTides()
        isLoading = false
    }

    private func refreshLocationAndSun() async {
        if store.selectedCode == SavedLocation.currentCode { _ = await store.resolveCurrent() }
        loadSunMoon()
    }

    private func loadSunMoon() {
        sunMoon = SunMoonService.shared.calculate(location: store.selected.sunMoon, date: activeDay)
    }

    private func loadMoonPhases() {
        // Show one year ahead in the mini-calendar (~25 phases/year; count is a safe cap).
        let horizon = Calendar.current.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
        moonPhases = MoonPhasesService.shared.nextPhases(from: selectedDate, count: 40)
            .filter { $0.datetime <= horizon }
        moonCalMonth = startOfMonth(selectedDate)
        selectedMoonDay = nil
    }

    private func loadTides() async {
        let station = ihmStations.first { $0.id == selectedTideStationId } ?? ihmStations.first { $0.id == "4" }!
        do { tidesPair = try await TidesService.shared.tides(for: selectedDate, stationId: station.id, stationName: station.name) } catch {}
    }

    private func loadAstroEvents() {
        // One year ahead of astronomical events (~20-30/year; count is a safe cap).
        let horizon = Calendar.current.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
        var events = AstroEventsService.shared.nextEvents(from: selectedDate, count: 60)
        // Solar turning points (earliest/latest sunrise & sunset) for the selected place.
        events += SunMoonService.shared
            .solarTurningPoints(location: store.selected.sunMoon, from: selectedDate, years: 1)
            .map { tp in
                AstroEvent(label: tp.kind.label, emoji: tp.kind.emoji,
                           details: "\(tp.kind.note) · \(hhmmLocal(tp.time))",
                           datetime: tp.time, date: isoDay(tp.day), timeLocal: hhmmLocal(tp.time))
            }
        astroEvents = events.filter { $0.datetime <= horizon }.sorted { $0.datetime < $1.datetime }
    }

    private func hhmmLocal(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_ES"); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func isoDay(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }
}
