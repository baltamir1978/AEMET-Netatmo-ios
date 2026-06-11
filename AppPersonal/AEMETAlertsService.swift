import Foundation

// MARK: - Alert model

enum AemetAlertLevel: Int, Comparable {
    case verde = 0, amarillo = 1, naranja = 2, rojo = 3

    init(name: String) {
        switch name.lowercased() {
        case "amarillo": self = .amarillo
        case "naranja":  self = .naranja
        case "rojo":     self = .rojo
        default:         self = .verde
        }
    }

    var name: String {
        switch self {
        case .verde: return "verde"; case .amarillo: return "amarillo"
        case .naranja: return "naranja"; case .rojo: return "rojo"
        }
    }

    static func < (a: AemetAlertLevel, b: AemetAlertLevel) -> Bool { a.rawValue < b.rawValue }
}

/// A single active AEMET weather warning that covers the queried point.
struct AemetAlert: Identifiable {
    let id = UUID()
    let phenomenon: String   // short label, e.g. "Tormentas"
    let event: String        // full AEMET headline-style text
    let level: AemetAlertLevel
    let areaDesc: String     // matched zone name
    let onset: Date?
    let expires: Date?
    let sfSymbol: String

    /// Compact badge for the App Group snapshot (widgets).
    var badge: AemetAlertBadge { AemetAlertBadge(level: level.rawValue, phenomenon: phenomenon) }
}

// MARK: - Service entry point (lives on AEMETService for the shared fetch helpers)

extension AEMETService {
    /// Active warnings covering `(lat, lon)`. Derives the CCAA area from the
    /// municipio's province (first two INE digits), fetches the CAP bundle, and
    /// keeps only the phenomena whose zone polygon contains the point. Caches the
    /// raw bundle (same disk cache as the forecast) and falls back to it on failure.
    func alerts(municipioCode: String, lat: Double, lon: Double,
                maxAge: TimeInterval? = nil) async throws -> [AemetAlert] {
        guard let area = AemetCAP.ccaaArea(forMunicipio: municipioCode) else { return [] }
        let key = "avisos_\(area)"
        let cached = AemetDiskCache.load(key)
        if let maxAge, let c = cached, c.age < maxAge {
            return AemetCAP.parse(tar: c.data, lat: lat, lon: lon)
        }
        do {
            let dataURL = try await fetchDataURL("\(base)/avisos_cap/ultimoelaborado/area/\(area)")
            // CAP payload is a binary tar — fetch raw, never re-encode as text.
            let (raw, _) = try await URLSession.shared.data(from: dataURL)
            AemetDiskCache.save(key, data: raw)
            return AemetCAP.parse(tar: raw, lat: lat, lon: lon)
        } catch {
            if let c = cached { return AemetCAP.parse(tar: c.data, lat: lat, lon: lon) }
            throw error
        }
    }
}

// MARK: - CAP parsing

enum AemetCAP {

    /// Parse a CAP `.tar` bundle, returning the warnings whose zone polygons
    /// contain the point, one per phenomenon at its highest covering level.
    static func parse(tar: Data, lat: Double, lon: Double) -> [AemetAlert] {
        var best: [String: AemetAlert] = [:]   // phenomenon → strongest covering alert
        for (_, xml) in TarReader.entries(in: tar) {
            let parser = CAPDocumentParser()
            for info in parser.parse(xml) where info.language.hasPrefix("es") {
                guard info.level > .verde else { continue }
                guard let area = info.areas.first(where: { $0.contains(lat: lat, lon: lon) }) else { continue }
                let alert = AemetAlert(
                    phenomenon: info.phenomenon,
                    event: info.event,
                    level: info.level,
                    areaDesc: area.desc,
                    onset: info.onset,
                    expires: info.expires,
                    sfSymbol: symbol(for: info.phenomenonCode)
                )
                if let existing = best[info.phenomenon], existing.level >= alert.level { continue }
                best[info.phenomenon] = alert
            }
        }
        return best.values.sorted { $0.level > $1.level }
    }

    /// AEMET municipio code (= INE code); first two digits are the province.
    static func ccaaArea(forMunicipio code: String) -> Int? {
        guard code.count >= 2, let prov = Int(code.prefix(2)) else { return nil }
        return provinceToArea[prov]
    }

    /// Province (INE 2-digit) → AEMET Meteoalerta CCAA area code (61–79).
    private static let provinceToArea: [Int: Int] = [
        4: 61, 11: 61, 14: 61, 18: 61, 21: 61, 23: 61, 29: 61, 41: 61,   // Andalucía
        22: 62, 44: 62, 50: 62,                                          // Aragón
        33: 63,                                                          // Asturias
        7: 64,                                                           // Baleares
        35: 65, 38: 65,                                                  // Canarias
        39: 66,                                                          // Cantabria
        5: 67, 9: 67, 24: 67, 34: 67, 37: 67, 40: 67, 42: 67, 47: 67, 49: 67, // Castilla y León
        2: 68, 13: 68, 16: 68, 19: 68, 45: 68,                          // Castilla-La Mancha
        8: 69, 17: 69, 25: 69, 43: 69,                                  // Cataluña
        6: 70, 10: 70,                                                  // Extremadura
        15: 71, 27: 71, 32: 71, 36: 71,                                 // Galicia
        28: 72,                                                         // Madrid
        30: 73,                                                         // Murcia
        31: 74,                                                         // Navarra
        1: 75, 20: 75, 48: 75,                                          // País Vasco
        26: 76,                                                         // La Rioja
        3: 77, 12: 77, 46: 77,                                          // Comunitat Valenciana
        51: 78,                                                         // Ceuta
        52: 79                                                          // Melilla
    ]

    /// Map AEMET phenomenon code (from the file name, e.g. "TO", "NE") to an SF Symbol.
    private static func symbol(for code: String) -> String {
        switch code {
        case "AT": return "thermometer.sun.fill"       // temperaturas máximas
        case "BT": return "thermometer.snowflake"      // temperaturas mínimas
        case "NE": return "snowflake"                  // nevadas
        case "PR", "PL": return "cloud.rain.fill"      // lluvias
        case "TO": return "cloud.bolt.rain.fill"       // tormentas
        case "VI": return "wind"                       // vientos
        case "NI": return "cloud.fog.fill"             // nieblas
        case "DH": return "drop.degreesign.fill"       // deshielos
        case "PS", "PV": return "sun.dust.fill"        // polvo en suspensión
        case "CO": return "water.waves"                // costeros
        default:   return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Minimal POSIX tar reader

private enum TarReader {
    /// Returns (filename, fileData) for each regular file in a POSIX/GNU tar.
    static func entries(in data: Data) -> [(name: String, body: Data)] {
        var out: [(String, Data)] = []
        let block = 512
        var offset = 0
        let bytes = [UInt8](data)
        while offset + block <= bytes.count {
            let header = Array(bytes[offset..<offset + block])
            // Two consecutive zero blocks mark the end; a zero name block ends parsing.
            if header.allSatisfy({ $0 == 0 }) { break }
            let name = cString(header, 0, 100)
            let sizeStr = cString(header, 124, 12).trimmingCharacters(in: .whitespaces)
            let size = Int(sizeStr, radix: 8) ?? 0
            offset += block
            if size > 0, offset + size <= bytes.count, !name.isEmpty {
                out.append((name, Data(bytes[offset..<offset + size])))
            }
            offset += (size + block - 1) / block * block   // advance past padded data
        }
        return out
    }

    private static func cString(_ b: [UInt8], _ start: Int, _ len: Int) -> String {
        let slice = b[start..<min(start + len, b.count)]
        let trimmed = slice.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self)
    }
}

// MARK: - CAP XML parser (one <alert> document, possibly multiple <info>)

private final class CAPDocumentParser: NSObject, XMLParserDelegate {
    struct Polygon { let points: [(lat: Double, lon: Double)] }
    struct Area {
        let desc: String
        let polygons: [Polygon]
        func contains(lat: Double, lon: Double) -> Bool {
            polygons.contains { pointInPolygon(lat: lat, lon: lon, polygon: $0.points) }
        }
    }
    struct Info {
        var language = ""
        var event = ""
        var phenomenon = ""
        var phenomenonCode = ""
        var level: AemetAlertLevel = .verde
        var onset: Date?
        var expires: Date?
        var areas: [Area] = []
    }

    private var infos: [Info] = []
    private var cur = Info()
    private var areaDesc = ""
    private var areaPolys: [Polygon] = []
    private var elem = ""
    private var text = ""
    private var lastValueName = ""   // tracks <valueName> so we can read the paired <value>

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func parse(_ data: Data) -> [Info] {
        infos = []
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return infos
    }

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        elem = el
        text = ""
        switch el {
        case "info": cur = Info()
        case "area": areaDesc = ""; areaPolys = []
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "language": cur.language = t
        case "event":    cur.event = t
        case "onset":    cur.onset = Self.iso.date(from: t)
        case "expires":  cur.expires = Self.iso.date(from: t)
        case "valueName": lastValueName = t
        case "value":
            if lastValueName.contains("fenomeno") {
                // e.g. "AT;Temperaturas máximas"
                let parts = t.components(separatedBy: ";")
                cur.phenomenonCode = parts.first ?? ""
                cur.phenomenon = parts.count > 1 ? parts[1] : t
            } else if lastValueName.contains("nivel") {
                cur.level = AemetAlertLevel(name: t)
            }
        case "areaDesc": areaDesc = t
        case "polygon":
            let pts = t.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { pair -> (Double, Double)? in
                let c = pair.split(separator: ",")
                guard c.count == 2, let la = Double(c[0]), let lo = Double(c[1]) else { return nil }
                return (la, lo)
            }
            if pts.count >= 3 { areaPolys.append(Polygon(points: pts.map { (lat: $0.0, lon: $0.1) })) }
        case "area":
            cur.areas.append(Area(desc: areaDesc, polygons: areaPolys))
        case "info":
            infos.append(cur)
        default: break
        }
        text = ""
    }
}

// MARK: - Point-in-polygon (ray casting; x = lon, y = lat)

private func pointInPolygon(lat: Double, lon: Double, polygon: [(lat: Double, lon: Double)]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
        let yi = polygon[i].lat, xi = polygon[i].lon
        let yj = polygon[j].lat, xj = polygon[j].lon
        if (yi > lat) != (yj > lat),
           lon < (xj - xi) * (lat - yi) / (yj - yi) + xi {
            inside.toggle()
        }
        j = i
    }
    return inside
}
