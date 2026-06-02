import SwiftUI

struct CosmosView: View {
    @State private var selectedDate = Date()
    @State private var selectedLocation = "lagranja"
    @AppStorage("tide_station_id") private var selectedTideStationId = "4"
    @State private var sunMoon: SunMoonResult?
    @State private var tidesPair: TidesDayPair?
    @State private var astroEvents: [AstroEvent]?
    @State private var isLoading = false

    private var dateISO: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if isLoading { ProgressView().padding(6) }
                    if let sm = sunMoon { sunMoonCard(sm) }
                    if let t = tidesPair { tidesCard(t) }
                    if let ev = astroEvents, !ev.isEmpty { astroCard(ev) }
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
                            .background(Color.blue).foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().scaleEffect(0.75) }
                        Picker("", selection: $selectedLocation) {
                            ForEach(sunMoonLocations) { loc in
                                Text(loc.name).tag(loc.key)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedLocation) { _, _ in loadSunMoon() }
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
                    Text("Iluminación \(Int(data.moon.illumination))%")
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

    // MARK: - Astro events card

    private func astroCard(_ events: [AstroEvent]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Próximos eventos astronómicos")
                    .font(.caption).fontWeight(.bold).textCase(.uppercase)
                    .foregroundStyle(.secondary).tracking(1)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            VStack(spacing: 6) {
                ForEach(events) { event in astroRow(event) }
            }
            .padding(10)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

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
                             : isSoon ? Color(red: 0.94, green: 0.97, blue: 1.0)
                             : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isToday ? Color.yellow : isSoon ? Color.blue.opacity(0.3) : Color.clear))
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
        isLoading = true
        loadSunMoon()
        loadAstroEvents()
        await loadTides()
        isLoading = false
    }

    private func loadSunMoon() {
        let loc = sunMoonLocations.first { $0.key == selectedLocation } ?? sunMoonLocations[0]
        sunMoon = SunMoonService.shared.calculate(location: loc, date: selectedDate)
    }

    private func loadTides() async {
        let station = ihmStations.first { $0.id == selectedTideStationId } ?? ihmStations.first { $0.id == "4" }!
        do { tidesPair = try await TidesService.shared.tides(for: selectedDate, stationId: station.id, stationName: station.name) } catch {}
    }

    private func loadAstroEvents() {
        astroEvents = AstroEventsService.shared.nextEvents(from: selectedDate)
    }
}
