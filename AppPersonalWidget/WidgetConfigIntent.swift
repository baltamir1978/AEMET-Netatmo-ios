import AppIntents
import WidgetKit

/// A location option shown in the widget's "Edit widget" configuration.
/// IDs: `__app__` (follow the app's selection), `__current__` (GPS), or a municipio code.
struct WidgetLocationEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Ubicación" }
    static var defaultQuery = WidgetLocationQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static let followApp = WidgetLocationEntity(id: "__app__", name: "Seguir la app")
    static let gps       = WidgetLocationEntity(id: SavedLocation.currentCode, name: "📍 Ubicación actual")
}

struct WidgetLocationQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetLocationEntity] {
        // `.followApp` is no longer *offered* (see `suggestedEntities`), but it stays
        // resolvable so a widget a user configured with it before still decodes and works.
        let all = Self.allOptions() + [.followApp]
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [WidgetLocationEntity] {
        Self.allOptions()
    }

    func defaultResult() async -> WidgetLocationEntity? { .gps }

    /// "📍 Ubicación actual" plus every followed city. "Seguir la app" was dropped: it
    /// duplicated "Ubicación actual" whenever the app itself was set to the GPS location,
    /// and the followed-city list already covers pinning the widget to a fixed town.
    static func allOptions() -> [WidgetLocationEntity] {
        [.gps] + WidgetStore.loadLocations().map {
            WidgetLocationEntity(id: $0.code, name: $0.name)
        }
    }
}

/// Any configuration intent that lets the user pick a location — so `resolveWidgetLocation`
/// works for both the Sol·Luna widget (location only) and the Tiempo widget (location + fondo).
protocol LocationSelectingIntent {
    var location: WidgetLocationEntity? { get }
}

/// Configuration intent for the Sol·Luna widget ("Editar widget" → Ubicación).
struct SelectLocationIntent: WidgetConfigurationIntent, LocationSelectingIntent {
    static var title: LocalizedStringResource = "Ubicación"
    static var description = IntentDescription("Elige la ciudad que muestra el widget, o usa tu ubicación actual.")

    @Parameter(title: "Ubicación")
    var location: WidgetLocationEntity?

    init() {}
}

/// Resolve the configured option to a concrete `SavedLocation`.
/// Nil (a freshly added widget) now defaults to the GPS location; "__app__" is only
/// reached by widgets a user configured before "Seguir la app" was retired.
func resolveWidgetLocation(_ intent: some LocationSelectingIntent) -> SavedLocation {
    switch intent.location?.id ?? SavedLocation.currentCode {
    case "__app__":
        return WidgetStore.selectedLocation()
    case SavedLocation.currentCode:
        return WidgetStore.loadResolvedCurrent() ?? WidgetStore.selectedLocation()
    case let code:
        return WidgetStore.loadLocations().first { $0.code == code } ?? WidgetStore.selectedLocation()
    }
}

// MARK: - Temperature-coloured background

/// Widget background: the app's green, or a colour driven by the current temperature
/// (deep blue near zero → deep red at 40-45°, see `TempPalette`). Offered as an option rather
/// than imposed: the colour is striking, but it also makes the widget change look every few
/// hours. Shared by the Netatmo widget (outdoor temp) and the Tiempo widget (AEMET temp).
enum TempBackground: String, AppEnum {
    case theme        // green, like the rest of the app
    case temperature  // colour by current temperature

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Fondo" }

    static var caseDisplayRepresentations: [TempBackground: DisplayRepresentation] = [
        .theme:       DisplayRepresentation(title: "Verde"),
        .temperature: DisplayRepresentation(title: "Color según la temperatura"),
    ]
}

/// Configuration intent for the Netatmo widget ("Editar widget" → Fondo).
struct NetatmoStyleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Estación Netatmo"
    static var description = IntentDescription("Elige si el fondo sigue el verde de la app o cambia con la temperatura exterior.")

    @Parameter(title: "Fondo", default: .theme)
    var background: TempBackground

    init() {}
}

/// Configuration intent for the Tiempo widget: pick the city *and* the background style.
struct WeatherStyleIntent: WidgetConfigurationIntent, LocationSelectingIntent {
    static var title: LocalizedStringResource = "Tiempo"
    static var description = IntentDescription("Elige la ciudad y si el fondo sigue el verde de la app o cambia con la temperatura.")

    @Parameter(title: "Ubicación")
    var location: WidgetLocationEntity?

    @Parameter(title: "Fondo", default: .theme)
    var background: TempBackground

    init() {}
}
