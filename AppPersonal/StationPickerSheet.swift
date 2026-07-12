import SwiftUI
import CoreLocation

/// Distance / altitude formatting shared by the station picker and the location card,
/// so both read the same. Locale-aware (comma decimals in es, point in en).
enum StationFormat {
    /// "9,9" under 10 km, "12" above — a tenth of a km only matters when stations are close.
    static func km(_ km: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .autoupdatingCurrent
        f.maximumFractionDigits = km < 10 ? 1 : 0
        return f.string(from: NSNumber(value: km)) ?? "\(Int(km))"
    }

    static func metres(_ alt: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .autoupdatingCurrent
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: alt)) ?? "\(Int(alt))"
    }
}

/// Lets the user choose which AEMET observation station a location reads from.
///
/// The automatic pick is simply the nearest station, which is usually right — but distance
/// alone is a poor proxy for "same weather". In the sierra the closest station can be 10 km
/// away on the *other* side of the mountain (El Paular, from La Granja) while the one 12 km
/// away (Segovia) shares your valley and altitude. So we list the nearby stations with the
/// two numbers that let you judge that — distance and altitude — and remember the pick.
struct StationPickerSheet: View {
    @ObservedObject private var store = LocationStore.shared
    @Environment(\.dismiss) private var dismiss

    /// Municipio the station is being chosen for (the GPS entry uses its resolved municipio).
    let code: String
    /// Coordinate the distances are measured from.
    let coord: CLLocationCoordinate2D
    /// Called after a pick, so the caller can re-fetch the observation.
    var onSelect: () -> Void

    @State private var nearby: [(station: AemetLiveStation, km: Double)] = []
    @State private var isLoading = true
    @State private var pinned: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if nearby.isEmpty {
                    Text("No se pudo cargar la red de estaciones de AEMET.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        automaticRow
                    } footer: {
                        Text("Automática usa la estación más cercana. Si está al otro lado de la montaña, elige a mano la que comparta tu valle o tu altitud.")
                    }
                    Section("Estaciones cercanas") {
                        ForEach(nearby, id: \.station.indicativo) { item in
                            stationRow(item.station, km: item.km)
                        }
                    }
                }
            }
            .navigationTitle("Estación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .task {
            pinned = store.pinnedStation(forCode: code)
            nearby = await store.nearbyStations(to: coord)
            isLoading = false
        }
    }

    private var automaticRow: some View {
        let nearest = nearby.first.map { LocationStore.shortStationName($0.station.nombre) }
        // On automatic, name the station actually in use (same value the Tiempo tab's card
        // shows) instead of recomputing "nearest" here — a city saved under an older rule
        // keeps its station until it's re-resolved, and the two screens must not disagree.
        // With a station pinned, "Ahora" describes what automatic *would* pick.
        let inUse = pinned == nil ? (store.stationName(forCode: code) ?? nearest) : nearest
        return Button {
            pick(nil)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automática").foregroundStyle(.primary)
                    if let inUse {
                        Text("Ahora: \(inUse)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if pinned == nil { checkmark }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(inUse.map { Text("Automática, la estación más cercana: \($0)") }
                            ?? Text("Automática"))
        .accessibilityAddTraits(pinned == nil ? [.isButton, .isSelected] : .isButton)
    }

    private func stationRow(_ s: AemetLiveStation, km: Double) -> some View {
        let name = LocationStore.shortStationName(s.nombre)
        return Button {
            pick(s)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    Text(detail(km: km, alt: s.alt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if pinned == s.indicativo { checkmark }
            }
        }
        // VoiceOver would otherwise read the abbreviations ("a 11 km · 1008 m") — spell the
        // units out, and mark the station in use as selected.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axLabel(name, km: km, alt: s.alt))
        .accessibilityAddTraits(pinned == s.indicativo ? [.isButton, .isSelected] : .isButton)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark").font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.green)
            .accessibilityHidden(true)      // the row carries the .isSelected trait
    }

    /// "a 9,9 km · 1.159 m"
    private func detail(km: Double, alt: Double?) -> String {
        let dist = StationFormat.km(km)
        guard let alt else { return String(localized: "a \(dist) km") }
        return String(localized: "a \(dist) km · \(StationFormat.metres(alt)) m")
    }

    private func axLabel(_ name: String, km: Double, alt: Double?) -> Text {
        let dist = StationFormat.km(km)
        guard let alt else { return Text("Estación \(name), a \(dist) kilómetros") }
        return Text("Estación \(name), a \(dist) kilómetros, altitud \(StationFormat.metres(alt)) metros")
    }

    private func pick(_ station: AemetLiveStation?) {
        pinned = station?.indicativo
        Task {
            await store.selectStation(station, forCode: code)
            onSelect()
            dismiss()
        }
    }
}
