import Foundation
import Combine
import CoreLocation

/// Una fila del buscador: un municipio, o un pueblo del nomenclátor con el municipio
/// que le da la previsión debajo ("Niembro · Llanes").
///
/// `nonisolated` y `Sendable` porque el índice se construye fuera del hilo principal.
nonisolated struct LocationSuggestion: Identifiable, Sendable, Hashable {
    /// Propio, no el código del municipio: varios pueblos comparten municipio y en una
    /// lista de SwiftUI dos filas con la misma identidad se pisan.
    let id: String
    let name: String
    /// El municipio al que pertenece, cuando la fila es un pueblo suyo.
    let municipality: String?
    /// Código AEMET (= INE) del municipio, o `pt-…` para Portugal.
    let code: String
    let lat: Double?
    let lon: Double?
}

/// El buscador de localidades: catálogo en memoria y consulta instantánea.
///
/// Antes cada caja de búsqueda pedía a AEMET el maestro de municipios *en la primera
/// tecla*: dos peticiones encadenadas, detrás del throttle de 1,2 s y con reintentos por
/// 429 — más de cinco segundos hasta ver la primera lista. Y después, cada pulsación
/// volvía a poner en minúsculas y plegar los acentos de los ~8.100 nombres.
///
/// Ahora el índice se arma en memoria una sola vez con los nombres ya normalizados, y
/// `search` es una llamada síncrona: se busca desde la primera letra, sin debounce.
/// Lleva tres fuentes:
///
///   · el nomenclátor embebido (`Nucleos.tsv`, ~29k pueblos con su código INE), que no
///     necesita red *ni clave*: es lo que hace que la primera búsqueda ya responda, y lo
///     que permite escribir "Niembro" en vez de conformarse con "Llanes";
///   · el maestro de municipios de AEMET, cacheado en disco un mes (los nombres
///     oficiales, y de dónde sale el municipio que se enseña bajo cada pueblo);
///   · las 35 localidades de IPMA, para que buscar "Faro" sea lo mismo que "Segovia".
final class LocationSearch: ObservableObject {
    static let shared = LocationSearch()

    /// El índice aún se está armando (o falta el catálogo de AEMET). Las vistas lo
    /// observan para avisar, y para repetir la consulta sola cuando termine.
    @Published private(set) var isLoading = false

    /// Una fila con su nombre ya normalizado.
    private nonisolated struct Entry: Sendable {
        let suggestion: LocationSuggestion
        /// El nombre en minúsculas, sin acentos y en UTF-8, calculado una vez al
        /// construir el índice. En bytes y no en `String` porque el repaso completo
        /// compara 30.000 nombres: en `String` cuesta 13 ms por tecla, en bytes 1.
        let folded: [UInt8]
        /// Un municipio entero, no un pueblo suyo: gana el empate al ordenar resultados.
        let isTown: Bool
        /// Habitantes del pueblo (0 en los municipios y donde GeoNames no los da).
        let population: Int
    }

    private var entries: [Entry] = []
    private var building: Task<Void, Never>?
    private var isFresh = false
    /// Sin clave de AEMET (o sin cobertura) la petición no puede salir bien: se espera un
    /// poco antes de repetirla, o cada tecla dispararía la suya.
    private var retryAfter = Date.distantPast

    /// El maestro sólo cambia cuando el INE crea o fusiona un municipio: con un mes de
    /// caché la red se toca una vez al mes y nunca delante del usuario.
    private let catalogMaxAge: TimeInterval = 30 * 24 * 60 * 60

    /// Última consulta resuelta. El cuerpo de una vista SwiftUI se recalcula muchas más
    /// veces de las que el usuario teclea, y los resultados son una propiedad calculada.
    private var lastKey: String?
    private var lastResults: [LocationSuggestion] = []

    /// Deja el índice listo antes de la primera tecla. Llamar al abrir una pantalla con
    /// buscador; repetirlo no cuesta nada.
    func prepare() {
        guard !isFresh, building == nil, Date() >= retryAfter else { return }
        isLoading = true
        building = Task {
            // Primera pasada con lo que hay sin salir a la red: el nomenclátor va dentro
            // de la app y el maestro suele estar en disco de la sesión anterior.
            let cached = AEMETService.shared.cachedMunicipios()
            await rebuild(towns: cached?.list ?? [])

            if let cached, cached.age < catalogMaxAge {
                isFresh = true
            } else {
                // Segunda pasada sólo si el maestro falta o ya tiene un mes. Mientras
                // baja, el buscador ya está respondiendo con el nomenclátor.
                let fresh = (try? await AEMETService.shared.allMunicipios(maxAge: catalogMaxAge)) ?? []
                if fresh.isEmpty {
                    retryAfter = Date().addingTimeInterval(60)
                } else {
                    await rebuild(towns: fresh)
                    isFresh = true
                }
            }
            isLoading = false
            building = nil
        }
    }

    /// Las localidades cuyo nombre contiene `query`, ordenadas por lo bien que encajan:
    /// primero las que empiezan por lo escrito, luego aquellas en las que empieza una
    /// palabra ("Villanueva del **Rey**"), y al final el resto de coincidencias. Dentro
    /// de cada grupo el municipio va antes que sus pueblos.
    func search(_ query: String, limit: Int = 15) -> [LocationSuggestion] {
        let folded = Self.fold(query)
        guard !folded.isEmpty else { return [] }
        let q = Array(folded.utf8)
        let key = "\(limit)|\(folded)"
        if key == lastKey { return lastResults }

        // El índice va ordenado, así que los nombres que empiezan por lo escrito son un
        // tramo seguido: se llega a él por bisección en vez de recorrer las ~30.000
        // entradas. Con las primeras letras —lo que más se teclea— ahí acaba el trabajo.
        var townStarts: [LocationSuggestion] = []
        var villageStarts: [LocationSuggestion] = []
        var i = lowerBound(q)
        while i < entries.count, Self.hasPrefix(entries[i].folded, q), townStarts.count < limit {
            let e = entries[i]
            if e.isTown { townStarts.append(e.suggestion) } else { villageStarts.append(e.suggestion) }
            i += 1
        }

        var results = Array((townStarts + villageStarts).prefix(limit))
        if results.count < limit {
            // Sólo cuando sobra sitio se paga el repaso completo, que es el único modo de
            // encontrar lo que va en medio del nombre.
            let spaced = [UInt8(ascii: " ")] + q
            var words: [LocationSuggestion] = []
            var villageWords: [LocationSuggestion] = []
            var rest: [LocationSuggestion] = []
            var villageRest: [LocationSuggestion] = []
            for e in entries where !Self.hasPrefix(e.folded, q) {
                if Self.contains(e.folded, spaced) {
                    if e.isTown { words.append(e.suggestion) } else { villageWords.append(e.suggestion) }
                } else if Self.contains(e.folded, q) {
                    if e.isTown { rest.append(e.suggestion) } else { villageRest.append(e.suggestion) }
                }
            }
            results = Array((townStarts + villageStarts + words + villageWords + rest + villageRest).prefix(limit))
        }

        lastKey = key
        lastResults = results
        return results
    }

    /// Primer índice cuyo nombre plegado alcanza `q` (bisección sobre el orden del índice).
    private func lowerBound(_ q: [UInt8]) -> Int {
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if Self.precedes(entries[mid].folded, q) { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: - Comparaciones sobre los nombres plegados

    private nonisolated static func hasPrefix(_ name: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= name.count else { return false }
        for i in 0..<needle.count where name[i] != needle[i] { return false }
        return true
    }

    private nonisolated static func contains(_ name: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, needle.count <= name.count else { return false }
        let first = needle[0]
        for i in 0...(name.count - needle.count) where name[i] == first {
            var j = 1
            while j < needle.count, name[i + j] == needle[j] { j += 1 }
            if j == needle.count { return true }
        }
        return false
    }

    private nonisolated static func precedes(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        a.lexicographicallyPrecedes(b)
    }

    /// Rehace el índice con los municipios que haya. Parsear el nomenclátor, plegar 37.000
    /// nombres y ordenarlos cuesta decenas de ms: va en una tarea de fondo para que abrir
    /// la pantalla no dé un tirón.
    private func rebuild(towns: [AemetMunicipio]) async {
        // Los tipos de AEMET e IPMA viven en el hilo principal; lo que cruza a la tarea
        // son ya filas planas.
        let spanish = towns.map {
            LocationSuggestion(id: "m:" + $0.codMunicipio, name: $0.nombre, municipality: nil,
                               code: $0.codMunicipio, lat: $0.lat, lon: $0.lon)
        }
        let portuguese = IPMA.locations.map {
            LocationSuggestion(id: "m:" + $0.code, name: $0.name, municipality: nil,
                               code: $0.code, lat: $0.lat, lon: $0.lon)
        }
        let built = await Task.detached(priority: .userInitiated) {
            Self.buildIndex(towns: spanish + portuguese)
        }.value
        entries = built
        lastKey = nil
        lastResults = []
    }

    /// Municipios + pueblos del nomenclátor, plegados y ordenados por nombre (y el
    /// municipio antes que un pueblo homónimo, para que "Segovia" salga primero).
    private nonisolated static func buildIndex(towns: [LocationSuggestion]) -> [Entry] {
        var entries: [Entry] = []
        entries.reserveCapacity(towns.count + 30_000)
        var townNames: [String: Set<String>] = [:]     // código INE → nombres del municipio
        var official: [String: String] = [:]           // código INE → nombre para enseñar

        for t in towns {
            let folded = fold(t.name)
            townNames[t.code, default: []].insert(folded)
            official[t.code] = t.name
            entries.append(Entry(suggestion: t, folded: Array(folded.utf8), isTown: true, population: 0))
        }

        var seen = Set<String>()
        for n in Nomenclator.searchable {
            let folded = fold(n.name)
            // El pueblo que se llama como su municipio ya está en la lista (y con el
            // nombre oficial de AEMET, que es el que la previsión conoce).
            if townNames[n.ine]?.contains(folded) == true { continue }
            let id = "n:\(n.ine):\(folded)"
            guard seen.insert(id).inserted else { continue }
            entries.append(Entry(
                suggestion: LocationSuggestion(id: id, name: n.name, municipality: official[n.ine],
                                               code: n.ine,
                                               lat: n.coord.latitude, lon: n.coord.longitude),
                folded: Array(folded.utf8),
                isTown: false,
                population: n.population))
        }

        // Por nombre, que es lo que permite llegar por bisección al tramo de un prefijo.
        // A igualdad de nombre manda el municipio, y entre pueblos homónimos el más
        // poblado: "Posada" son seis pueblos, y quien lo escribe busca el de Llanes.
        entries.sort { a, b in
            if a.folded != b.folded { return precedes(a.folded, b.folded) }
            if a.isTown != b.isTown { return a.isTown }
            return a.population > b.population
        }
        return entries
    }

    private nonisolated static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }
}
