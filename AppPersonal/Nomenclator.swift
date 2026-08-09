import Foundation
import CoreLocation

/// Los núcleos de población de España, para poner nombre al sitio donde estás cuando
/// no es un municipio.
///
/// Apple sólo geocodifica hasta el municipio: en todo el concejo de Llanes devuelve
/// "Llanes" con `subLocality` nil, así que Posada de Llanes, Niembro y la villa salen
/// con el mismo nombre (sólo cambia el código postal). Media España rural es así —
/// parroquias asturianas, pedanías, lugares — y ver el nombre del municipio cuando
/// estás en un pueblo a 12 km de la capital se lee como un error de la app.
///
/// Los datos salen de `Tools/build_nomenclator.py` (GeoNames, CC BY 4.0) a
/// `Nucleos.tsv`, ordenado por latitud.
/// `nonisolated` a propósito: cargar y parsear el fichero cuesta decenas de ms, y con
/// el aislamiento por defecto del proyecto (MainActor) eso se pagaría bloqueando la UI.
/// Así el llamante puede resolverlo en una tarea de fondo.
nonisolated enum Nomenclator {
    struct Nucleo: Sendable {
        let name: String
        let coord: CLLocationCoordinate2D
        /// Código INE del municipio, el mismo con el que AEMET indexa su catálogo.
        /// Vacío en el ~1% de entradas que el dump no trae ancladas.
        let ine: String
    }

    /// Radio máximo para aceptar un núcleo. Un pueblo es un punto, no un polígono: el
    /// dump da su centro, así que el fix cae a cientos de metros del casco y no en él.
    /// 4 km cubre estar en las afueras sin llegar a nombrarte el pueblo de al lado —
    /// en el concejo de Llanes los núcleos se pisan cada 2-3 km.
    private static let maxDistanceKm = 4.0

    /// Cargado en el primer uso y retenido: son ~29k entradas, y resolver la ubicación
    /// vuelve a ocurrir cada vez que te mueves.
    private static let all: [Nucleo] = load()

    private static func load() -> [Nucleo] {
        guard let url = Bundle.main.url(forResource: "Nucleos", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Nucleo] = []
        out.reserveCapacity(30_000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 4, let lat = Double(f[0]), let lon = Double(f[1]) else { continue }
            out.append(Nucleo(name: String(f[3]),
                              coord: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                              ine: String(f[2])))
        }
        return out
    }

    /// El núcleo habitado más cercano a `coord`, o nil si no hay ninguno a tiro.
    ///
    /// Con `ine` no vacío la búsqueda se limita a ese municipio: el municipio ya lo
    /// resolvió AEMET, y anclar a él evita el fallo bochornoso de nombrarte un pueblo
    /// del concejo vecino porque su centro caiga un poco más cerca que el tuyo.
    static func nearest(to coord: CLLocationCoordinate2D, ine: String? = nil) -> Nucleo? {
        // El fichero va ordenado por latitud: descartar por banda evita medir 29k
        // distancias (1° de latitud son ~111 km, así que el radio es un margen amplio).
        let band = maxDistanceKm / 111.0
        var best: Nucleo?
        var bestKm = Double.greatestFiniteMagnitude
        var i = lowerBound(latitude: coord.latitude - band)
        while i < all.count, all[i].coord.latitude <= coord.latitude + band {
            let n = all[i]
            i += 1
            if let ine, !ine.isEmpty, !n.ine.isEmpty, n.ine != ine { continue }
            let km = distanceKm(coord, n.coord)
            if km < bestKm { bestKm = km; best = n }
        }
        return bestKm <= maxDistanceKm ? best : nil
    }

    /// Primer índice cuya latitud alcanza `latitude` (búsqueda binaria sobre el orden
    /// del fichero).
    private static func lowerBound(latitude: Double) -> Int {
        var lo = 0, hi = all.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if all[mid].coord.latitude < latitude { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }
}
