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
        let all = Self.allOptions()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [WidgetLocationEntity] {
        Self.allOptions()
    }

    func defaultResult() async -> WidgetLocationEntity? { .followApp }

    static func allOptions() -> [WidgetLocationEntity] {
        [.followApp, .gps] + WidgetStore.loadLocations().map {
            WidgetLocationEntity(id: $0.code, name: $0.name)
        }
    }
}

/// Configuration intent backing both widgets ("Editar widget" → Ubicación).
struct SelectLocationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Ubicación"
    static var description = IntentDescription("Elige la ciudad que muestra el widget, o usa tu ubicación actual.")

    @Parameter(title: "Ubicación")
    var location: WidgetLocationEntity?

    init() {}
}

/// Resolve the configured option to a concrete `SavedLocation`.
func resolveWidgetLocation(_ intent: SelectLocationIntent) -> SavedLocation {
    switch intent.location?.id ?? "__app__" {
    case "__app__":
        return WidgetStore.selectedLocation()
    case SavedLocation.currentCode:
        return WidgetStore.loadResolvedCurrent() ?? WidgetStore.selectedLocation()
    case let code:
        return WidgetStore.loadLocations().first { $0.code == code } ?? WidgetStore.selectedLocation()
    }
}
