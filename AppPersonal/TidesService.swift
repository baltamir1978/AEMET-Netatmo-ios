import Foundation

// MARK: - Station catalog (IHM GetList, sorted alphabetically)

struct TideStation: Identifiable {
    let id: String
    let name: String
}

let ihmStations: [TideStation] = [
    TideStation(id: "20", name: "A Coruña"),
    TideStation(id: "71", name: "A Guarda"),
    TideStation(id: "49", name: "Algeciras"),
    TideStation(id: "14", name: "Alúmina Española (San Cibrao)"),
    TideStation(id: "57", name: "Arinaga (Gran Canaria)"),
    TideStation(id: "53", name: "Arrecife (Lanzarote)"),
    TideStation(id: "7",  name: "Avilés (San Juan de Nieva)"),
    TideStation(id: "32", name: "Ayamonte"),
    TideStation(id: "30", name: "Baiona"),
    TideStation(id: "47", name: "Barbate"),
    TideStation(id: "72", name: "Bermeo"),
    TideStation(id: "2",  name: "Bilbao"),
    TideStation(id: "37", name: "Bonanza (Sanlúcar de Barrameda)"),
    TideStation(id: "13", name: "Burela"),
    TideStation(id: "42", name: "Cádiz"),
    TideStation(id: "22", name: "Camariñas"),
    TideStation(id: "16", name: "Cariño"),
    TideStation(id: "17", name: "Cedeira"),
    TideStation(id: "51", name: "Ceuta"),
    TideStation(id: "39", name: "Chipiona"),
    TideStation(id: "15", name: "Cillero (Ría de Viveiro)"),
    TideStation(id: "46", name: "Conil"),
    TideStation(id: "8",  name: "Cudillero"),
    TideStation(id: "41", name: "El Puerto de Santa María"),
    TideStation(id: "18", name: "Ferrol"),
    TideStation(id: "23", name: "Fisterra"),
    TideStation(id: "12", name: "Foz"),
    TideStation(id: "44", name: "Gallineras"),
    TideStation(id: "6",  name: "Gijón"),
    TideStation(id: "64", name: "Granadilla (Tenerife)"),
    TideStation(id: "34", name: "Isla Cristina"),
    TideStation(id: "43", name: "La Carraca"),
    TideStation(id: "70", name: "Langosteira (A Coruña exterior)"),
    TideStation(id: "31", name: "Lisboa"),
    TideStation(id: "4",  name: "Llanes"),
    TideStation(id: "63", name: "Los Cristianos (Tenerife)"),
    TideStation(id: "61", name: "Los Gigantes (Tenerife)"),
    TideStation(id: "21", name: "Malpica"),
    TideStation(id: "33", name: "Marina de Isla Canela"),
    TideStation(id: "28", name: "Marín (Ría de Pontevedra)"),
    TideStation(id: "36", name: "Mazagón (Huelva)"),
    TideStation(id: "55", name: "Morro Jable (Fuerteventura)"),
    TideStation(id: "9",  name: "Navia"),
    TideStation(id: "1",  name: "Pasajes"),
    TideStation(id: "58", name: "Pasito Blanco (Gran Canaria)"),
    TideStation(id: "24", name: "Portosín (Ría de Muros y Noia)"),
    TideStation(id: "62", name: "Puerto de la Cruz (Tenerife)"),
    TideStation(id: "67", name: "Puerto de la Estaca (El Hierro)"),
    TideStation(id: "56", name: "Puerto de la Luz (Gran Canaria)"),
    TideStation(id: "59", name: "Puerto de las Nieves (Gran Canaria)"),
    TideStation(id: "54", name: "Puerto del Rosario (Fuerteventura)"),
    TideStation(id: "35", name: "Punta Umbría"),
    TideStation(id: "11", name: "Ribadeo"),
    TideStation(id: "5",  name: "Ribadesella"),
    TideStation(id: "40", name: "Rota"),
    TideStation(id: "19", name: "Sada Fontán (Ría de Betanzos)"),
    TideStation(id: "65", name: "San Sebastián de la Gomera"),
    TideStation(id: "66", name: "Santa Cruz de La Palma"),
    TideStation(id: "60", name: "Santa Cruz de Tenerife"),
    TideStation(id: "25", name: "Santa Uxía de Ribeíra (Ría de Arousa)"),
    TideStation(id: "45", name: "Sancti Petri"),
    TideStation(id: "3",  name: "Santander"),
    TideStation(id: "27", name: "Sanxenxo (Ría de Pontevedra)"),
    TideStation(id: "38", name: "Sevilla"),
    TideStation(id: "50", name: "Sotogrande"),
    TideStation(id: "52", name: "Tánger"),
    TideStation(id: "10", name: "Tapia"),
    TideStation(id: "48", name: "Tarifa"),
    TideStation(id: "29", name: "Vigo"),
    TideStation(id: "26", name: "Vilagarcía (Ría de Arousa)"),
]

// MARK: - Service

struct TidesService {
    static let shared = TidesService()
    private let base = "https://ideihm.covam.es/api-ihm/getmarea"

    func tides(for date: Date, stationId: String = "4", stationName: String = "Llanes") async throws -> TidesDayPair {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "Europe/Madrid")

        let cal = Calendar.current
        var days: [TideDayResult] = []
        for offset in 0...1 {
            let d = cal.date(byAdding: .day, value: offset, to: date)!
            let dateStr = fmt.string(from: d)
            var comps = URLComponents(string: base)!
            comps.queryItems = [
                URLQueryItem(name: "request", value: "gettide"),
                URLQueryItem(name: "id",      value: stationId),
                URLQueryItem(name: "format",  value: "json"),
                URLQueryItem(name: "date",    value: dateStr),
            ]
            let isoDate = ISO8601DateFormatter()
            isoDate.formatOptions = [.withFullDate]
            isoDate.timeZone = TimeZone(identifier: "Europe/Madrid")
            do {
                let (data, _) = try await URLSession.shared.data(from: comps.url!)
                let resp = try JSONDecoder().decode(IHMResponse.self, from: data)
                var tideList = resp.mareas?.datos?.marea ?? []
                if tideList.isEmpty, let single = resp.mareas?.datos?.mareaOne {
                    tideList = [single]
                }
                days.append(TideDayResult(
                    date: isoDate.string(from: d),
                    tides: tideList.map { Tide(time: $0.hora ?? "—", height: Double($0.altura ?? "0") ?? 0, type: $0.tipo ?? "") }
                ))
            } catch {
                days.append(TideDayResult(date: isoDate.string(from: d), tides: []))
            }
        }
        return TidesDayPair(station: stationName, days: days)
    }
}

// MARK: - Result types

struct TidesDayPair {
    let station: String
    let days: [TideDayResult]
}

struct TideDayResult: Identifiable {
    var id: String { date }
    let date: String
    let tides: [Tide]
}

// MARK: - IHM JSON models

private struct IHMResponse: Decodable {
    let mareas: IHMMareas?
}

private struct IHMMareas: Decodable {
    let datos: IHMDatos?
}

private struct IHMDatos: Decodable {
    let marea: [IHMTide]?
    let mareaOne: IHMTide?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decode([IHMTide].self, forKey: .marea) {
            marea = arr; mareaOne = nil
        } else if let one = try? c.decode(IHMTide.self, forKey: .marea) {
            marea = nil; mareaOne = one
        } else {
            marea = nil; mareaOne = nil
        }
    }
    enum CodingKeys: String, CodingKey { case marea }
}

private struct IHMTide: Decodable {
    let hora: String?
    let altura: String?
    let tipo: String?
}
