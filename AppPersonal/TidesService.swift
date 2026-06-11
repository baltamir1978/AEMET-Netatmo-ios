import Foundation

// MARK: - Station catalog (IHM GetList, sorted alphabetically)

struct TideStation: Identifiable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
}

// MARK: - Tide (used by TidesService, CosmosView and the tides widget)

struct Tide: Identifiable {
    var id: String { time + type }
    let time: String
    let height: Double
    let type: String
}

let ihmStations: [TideStation] = [
    TideStation(id: "20", name: "A Coruña",                       lat: 43.37, lon: -8.40),
    TideStation(id: "71", name: "A Guarda",                       lat: 41.90, lon: -8.87),
    TideStation(id: "49", name: "Algeciras",                      lat: 36.13, lon: -5.44),
    TideStation(id: "14", name: "Alúmina Española (San Cibrao)",  lat: 43.70, lon: -7.43),
    TideStation(id: "57", name: "Arinaga (Gran Canaria)",         lat: 27.85, lon: -15.39),
    TideStation(id: "53", name: "Arrecife (Lanzarote)",           lat: 28.96, lon: -13.55),
    TideStation(id: "7",  name: "Avilés (San Juan de Nieva)",     lat: 43.58, lon: -5.95),
    TideStation(id: "32", name: "Ayamonte",                       lat: 37.21, lon: -7.41),
    TideStation(id: "30", name: "Baiona",                         lat: 42.12, lon: -8.85),
    TideStation(id: "47", name: "Barbate",                        lat: 36.19, lon: -5.92),
    TideStation(id: "72", name: "Bermeo",                         lat: 43.42, lon: -2.72),
    TideStation(id: "2",  name: "Bilbao",                         lat: 43.35, lon: -3.04),
    TideStation(id: "37", name: "Bonanza (Sanlúcar de Barrameda)",lat: 36.81, lon: -6.34),
    TideStation(id: "13", name: "Burela",                         lat: 43.66, lon: -7.35),
    TideStation(id: "42", name: "Cádiz",                          lat: 36.53, lon: -6.28),
    TideStation(id: "22", name: "Camariñas",                      lat: 43.13, lon: -9.18),
    TideStation(id: "16", name: "Cariño",                         lat: 43.74, lon: -7.87),
    TideStation(id: "17", name: "Cedeira",                        lat: 43.66, lon: -8.06),
    TideStation(id: "51", name: "Ceuta",                          lat: 35.89, lon: -5.31),
    TideStation(id: "39", name: "Chipiona",                       lat: 36.74, lon: -6.43),
    TideStation(id: "15", name: "Cillero (Ría de Viveiro)",       lat: 43.67, lon: -7.59),
    TideStation(id: "46", name: "Conil",                          lat: 36.28, lon: -6.09),
    TideStation(id: "8",  name: "Cudillero",                      lat: 43.56, lon: -6.15),
    TideStation(id: "41", name: "El Puerto de Santa María",       lat: 36.60, lon: -6.23),
    TideStation(id: "18", name: "Ferrol",                         lat: 43.48, lon: -8.24),
    TideStation(id: "23", name: "Fisterra",                       lat: 42.91, lon: -9.27),
    TideStation(id: "12", name: "Foz",                            lat: 43.57, lon: -7.26),
    TideStation(id: "44", name: "Gallineras",                     lat: 36.44, lon: -6.21),
    TideStation(id: "6",  name: "Gijón",                          lat: 43.55, lon: -5.70),
    TideStation(id: "64", name: "Granadilla (Tenerife)",          lat: 28.07, lon: -16.50),
    TideStation(id: "34", name: "Isla Cristina",                  lat: 37.20, lon: -7.32),
    TideStation(id: "43", name: "La Carraca",                     lat: 36.49, lon: -6.20),
    TideStation(id: "70", name: "Langosteira (A Coruña exterior)",lat: 43.35, lon: -8.50),
    TideStation(id: "31", name: "Lisboa",                         lat: 38.71, lon: -9.14),
    TideStation(id: "4",  name: "Llanes",                         lat: 43.42, lon: -4.75),
    TideStation(id: "63", name: "Los Cristianos (Tenerife)",      lat: 28.05, lon: -16.72),
    TideStation(id: "61", name: "Los Gigantes (Tenerife)",        lat: 28.24, lon: -16.84),
    TideStation(id: "21", name: "Malpica",                        lat: 43.32, lon: -8.81),
    TideStation(id: "33", name: "Marina de Isla Canela",          lat: 37.18, lon: -7.36),
    TideStation(id: "28", name: "Marín (Ría de Pontevedra)",      lat: 42.39, lon: -8.70),
    TideStation(id: "36", name: "Mazagón (Huelva)",               lat: 37.13, lon: -6.83),
    TideStation(id: "55", name: "Morro Jable (Fuerteventura)",    lat: 28.05, lon: -14.35),
    TideStation(id: "9",  name: "Navia",                          lat: 43.54, lon: -6.72),
    TideStation(id: "1",  name: "Pasajes",                        lat: 43.32, lon: -1.92),
    TideStation(id: "58", name: "Pasito Blanco (Gran Canaria)",   lat: 27.75, lon: -15.66),
    TideStation(id: "24", name: "Portosín (Ría de Muros y Noia)", lat: 42.76, lon: -8.94),
    TideStation(id: "62", name: "Puerto de la Cruz (Tenerife)",   lat: 28.42, lon: -16.55),
    TideStation(id: "67", name: "Puerto de la Estaca (El Hierro)",lat: 27.78, lon: -17.89),
    TideStation(id: "56", name: "Puerto de la Luz (Gran Canaria)",lat: 28.14, lon: -15.42),
    TideStation(id: "59", name: "Puerto de las Nieves (Gran Canaria)", lat: 28.10, lon: -15.71),
    TideStation(id: "54", name: "Puerto del Rosario (Fuerteventura)", lat: 28.50, lon: -13.86),
    TideStation(id: "35", name: "Punta Umbría",                   lat: 37.18, lon: -6.96),
    TideStation(id: "11", name: "Ribadeo",                        lat: 43.54, lon: -7.04),
    TideStation(id: "5",  name: "Ribadesella",                    lat: 43.46, lon: -5.06),
    TideStation(id: "40", name: "Rota",                           lat: 36.62, lon: -6.36),
    TideStation(id: "19", name: "Sada Fontán (Ría de Betanzos)",  lat: 43.35, lon: -8.25),
    TideStation(id: "65", name: "San Sebastián de la Gomera",     lat: 28.09, lon: -17.11),
    TideStation(id: "66", name: "Santa Cruz de La Palma",         lat: 28.68, lon: -17.76),
    TideStation(id: "60", name: "Santa Cruz de Tenerife",         lat: 28.47, lon: -16.25),
    TideStation(id: "25", name: "Santa Uxía de Ribeíra (Ría de Arousa)", lat: 42.55, lon: -8.99),
    TideStation(id: "45", name: "Sancti Petri",                   lat: 36.39, lon: -6.21),
    TideStation(id: "3",  name: "Santander",                      lat: 43.46, lon: -3.80),
    TideStation(id: "27", name: "Sanxenxo (Ría de Pontevedra)",   lat: 42.40, lon: -8.81),
    TideStation(id: "38", name: "Sevilla",                        lat: 37.33, lon: -6.00),
    TideStation(id: "50", name: "Sotogrande",                     lat: 36.28, lon: -5.27),
    TideStation(id: "52", name: "Tánger",                         lat: 35.78, lon: -5.81),
    TideStation(id: "10", name: "Tapia",                          lat: 43.57, lon: -6.94),
    TideStation(id: "48", name: "Tarifa",                         lat: 36.01, lon: -5.61),
    TideStation(id: "29", name: "Vigo",                           lat: 42.24, lon: -8.73),
    TideStation(id: "26", name: "Vilagarcía (Ría de Arousa)",     lat: 42.60, lon: -8.77),
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
