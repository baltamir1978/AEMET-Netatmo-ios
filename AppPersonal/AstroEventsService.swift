import Foundation

// Astronomical events: equinoxes, solstices (Meeus ch.27) + hardcoded eclipse table
// Eclipse data: NASA / Fred Espenak 2025-2030

struct AstroEvent: Identifiable {
    var id: String { label + date + timeLocal }
    let label: String
    let emoji: String
    let details: String?
    let datetime: Date
    let date: String        // YYYY-MM-DD local
    let timeLocal: String   // HH:MM local
}

struct AstroEventsService {
    static let shared = AstroEventsService()
    private let tz = TimeZone(identifier: "Europe/Madrid")!

    func nextEvents(from startDate: Date, count: Int = 8) -> [AstroEvent] {
        let equinoxes  = equinoxesAndSolstices(nearDate: startDate, count: count + 10)
        let eclipses   = eclipseEvents()
        var all = (equinoxes + eclipses).filter { $0.datetime >= startDate }
        all.sort { $0.datetime < $1.datetime }
        return Array(all.prefix(count))
    }

    // MARK: - Equinoxes & Solstices (Meeus ch. 27)

    private func equinoxesAndSolstices(nearDate: Date, count: Int) -> [AstroEvent] {
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: nearDate)
        var events: [AstroEvent] = []

        // Generate for year-1 to year+3 to cover "count" upcoming events
        for y in (year - 1)...(year + 3) {
            events.append(contentsOf: yearEquinoxesSolstices(year: y))
        }
        return events
    }

    private func yearEquinoxesSolstices(year: Int) -> [AstroEvent] {
        // Meeus table 27.a / 27.b (valid 1000–3000)
        let Y = Double(year)
        let k = (Y - 2000.0) / 1000.0

        // JDE0 for each event (mean values, table 27.a)
        let marchJDE0 = 2451623.80984 + 365242.37404 * k + 0.05169 * k*k
                       - 0.00411 * k*k*k - 0.00057 * k*k*k*k
        let juneJDE0  = 2451716.56767 + 365241.62603 * k + 0.00325 * k*k
                       + 0.00888 * k*k*k - 0.00030 * k*k*k*k
        let septJDE0  = 2451810.21715 + 365242.01767 * k - 0.11575 * k*k
                       + 0.00337 * k*k*k + 0.00078 * k*k*k*k
        let decJDE0   = 2451900.05952 + 365242.74049 * k - 0.06223 * k*k
                       - 0.00823 * k*k*k + 0.00032 * k*k*k*k

        return [
            makeEvent(jde: correctedJDE(marchJDE0), label: "Equinoccio de primavera", emoji: "🌸", details: nil),
            makeEvent(jde: correctedJDE(juneJDE0),  label: "Solsticio de verano",     emoji: "☀️",  details: nil),
            makeEvent(jde: correctedJDE(septJDE0),  label: "Equinoccio de otoño",     emoji: "🍂", details: nil),
            makeEvent(jde: correctedJDE(decJDE0),   label: "Solsticio de invierno",   emoji: "❄️",  details: nil),
        ].compactMap { $0 }
    }

    /// Apply periodic corrections from Meeus table 27.b
    private func correctedJDE(_ jde0: Double) -> Double {
        let T  = (jde0 - 2451545.0) / 36525.0
        let W  = 35999.373 * T - 2.47
        let dL = 1 + 0.0334 * cos(W.rad) + 0.0007 * cos(2 * W.rad)
        // Sum of 24 periodic terms (abbreviated — major terms only for brevity)
        let S  = 485 * cos((324.96 +  1934.136 * T).rad)
               + 203 * cos((337.23 + 32964.467 * T).rad)
               + 199 * cos((342.08 +    20.186 * T).rad)
               + 182 * cos(( 27.85 + 445267.112 * T).rad)
               + 156 * cos(( 73.14 + 45036.886  * T).rad)
               + 136 * cos((171.52 + 22518.443  * T).rad)
               +  77 * cos((222.54 + 65928.934  * T).rad)
               +  74 * cos(( 41.10 +  3034.906  * T).rad)
               +  70 * cos((213.92 + 63235.085  * T).rad)
               +  58 * cos(( 74.03 + 16859.071  * T).rad)
               +  52 * cos((177.41 + 26895.292  * T).rad)
               +  50 * cos(( 28.70 +  4443.772  * T).rad)
               +  45 * cos(( 28.24 + 63351.548  * T).rad)
               +  44 * cos(( 18.91 + 78495.651  * T).rad)
               +  29 * cos((207.19 +   253.032  * T).rad)
               +  18 * cos(( 29.57 +  9037.513  * T).rad)
               +  17 * cos(( 19.35 + 37935.000  * T).rad)
               +  16 * cos((154.84 +  2281.226  * T).rad)
               +  14 * cos(( 45.70 + 20601.048  * T).rad)
               +  12 * cos(( 44.57 + 23871.000  * T).rad)
               +  12 * cos(( 55.72 + 22279.690  * T).rad)
               +   9 * cos(( 23.39 + 10263.100  * T).rad)
               +   8 * cos(( 28.36 +  1222.114  * T).rad)
               +   7 * cos((154.84 + 9584.000   * T).rad)
        return jde0 + (0.00001 * S) / dL
    }

    private func makeEvent(jde: Double, label: String, emoji: String, details: String?) -> AstroEvent? {
        let date = jdeToDate(jde)
        return eventWithDates(date: date, label: label, emoji: emoji, details: details)
    }

    // MARK: - Eclipse table (NASA / Espenak, TD treated as UTC)

    private func eclipseEvents() -> [AstroEvent] {
        let raw: [(String, String, String, String)] = [
            // (datetime UTC approx, label, emoji, details)
            ("2026-02-17T12:12", "Eclipse de luna penumbral",   "🌝", "Penumbral, visible Europa"),
            ("2026-08-12T17:46", "Eclipse de sol total",        "🌑", "Total, visible N. Atlántico, Groenlandia"),
            ("2027-02-06T22:00", "Eclipse de luna penumbral",   "🌝", "Penumbral"),
            ("2027-08-02T10:07", "Eclipse de sol total",        "🌑", "Total, visible N. África, Oriente Medio"),
            ("2028-01-26T15:13", "Eclipse de luna total",       "🌕", "Total, visible Europa, África, Asia"),
            ("2028-07-22T02:57", "Eclipse de sol total",        "🌑", "Total, visible Australia, Nueva Zelanda"),
            ("2029-01-14T17:21", "Eclipse de luna total",       "🌕", "Total, visible Europa, América"),
            ("2029-06-12T04:06", "Eclipse de luna parcial",     "🌗", "Parcial"),
            ("2029-07-11T15:37", "Eclipse de sol parcial",      "🌑", "Parcial, hemisferio sur"),
            ("2030-01-05T17:55", "Eclipse de luna penumbral",   "🌝", "Penumbral"),
            ("2030-06-01T06:21", "Eclipse de sol anular",       "🌑", "Anular, visible N. África, Asia"),
            ("2030-11-25T06:52", "Eclipse de sol total",        "🌑", "Total, visible Namibia, Australia"),
        ]

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        isoFmt.timeZone = TimeZone(secondsFromGMT: 0)

        return raw.compactMap { (dtStr, label, emoji, details) in
            guard let date = isoFmt.date(from: dtStr + ":00Z") else { return nil }
            return eventWithDates(date: date, label: label, emoji: emoji, details: details)
        }
    }

    // MARK: - Helpers

    private func eventWithDates(date: Date, label: String, emoji: String, details: String?) -> AstroEvent {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        isoFmt.timeZone = tz

        let timeFmt = DateFormatter()
        timeFmt.timeZone = tz
        timeFmt.dateFormat = "HH:mm"

        return AstroEvent(
            label: label, emoji: emoji, details: details,
            datetime: date,
            date: isoFmt.string(from: date),
            timeLocal: timeFmt.string(from: date)
        )
    }

    /// Convert Julian Ephemeris Day to Date (TD ≈ UTC for our purposes)
    private func jdeToDate(_ jde: Double) -> Date {
        // JDE to Unix timestamp: JDE 2440587.5 = 1970-01-01 00:00 UTC
        let unixTime = (jde - 2440587.5) * 86400
        return Date(timeIntervalSince1970: unixTime)
    }
}

private extension Double {
    var rad: Double { self * .pi / 180 }
}
