import Foundation

// Upcoming New Moons and Full Moons (Meeus, Astronomical Algorithms, ch. 49).
// Times accurate to ~1 minute. TD treated as UTC for display purposes.

struct MoonPhaseEvent: Identifiable {
    enum Kind { case new, full }
    var id: String { date + timeLocal + label }
    let kind: Kind
    let label: String
    let emoji: String
    let datetime: Date
    let date: String        // YYYY-MM-DD local
    let timeLocal: String   // HH:mm local
}

struct MoonPhasesService {
    static let shared = MoonPhasesService()
    /// Zone the phase instants are printed in. A new moon happens at one instant
    /// worldwide, but the clock time you read it at is the location's — Lisboa is an hour
    /// behind Madrid, so a Portuguese location has to build its own instance.
    let tz: TimeZone

    init(tz: TimeZone = TimeZone(identifier: "Europe/Madrid")!) { self.tz = tz }

    /// Instance that prints in a location's own timezone (`SavedLocation.tz`).
    static func forZone(_ identifier: String) -> MoonPhasesService {
        MoonPhasesService(tz: TimeZone(identifier: identifier) ?? .current)
    }

    /// Next `count` principal phases (new + full) at or after `startDate`, sorted by date.
    func nextPhases(from startDate: Date, count: Int = 8) -> [MoonPhaseEvent] {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .dayOfYear], from: startDate)
        let yearFraction = Double(comps.year!) + Double(comps.dayOfYear ?? 1) / 365.25
        let k0 = floor((yearFraction - 2000.0) * 12.3685) - 2

        var events: [MoonPhaseEvent] = []
        var k = k0
        while events.count < count + 4 {
            events.append(phase(k: k, kind: .new))
            events.append(phase(k: k + 0.5, kind: .full))
            k += 1
        }
        return events
            .filter { $0.datetime >= startDate }
            .sorted { $0.datetime < $1.datetime }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - Meeus 49

    private func phase(k: Double, kind: MoonPhaseEvent.Kind) -> MoonPhaseEvent {
        let T = k / 1236.85
        let T2 = T * T, T3 = T2 * T, T4 = T3 * T

        var jde = 2451550.09766 + 29.530588861 * k
                + 0.00015437 * T2 - 0.000000150 * T3 + 0.00000000073 * T4

        let E = 1 - 0.002516 * T - 0.0000074 * T2
        let M  = (2.5534   + 29.10535670  * k - 0.0000014  * T2 - 0.00000011 * T3).rad
        let Mp = (201.5643 + 385.81693528 * k + 0.0107582  * T2 + 0.00001238 * T3 - 0.000000058 * T4).rad
        let F  = (160.7108 + 390.67050284 * k - 0.0016118  * T2 - 0.00000227 * T3 + 0.000000011 * T4).rad
        let Om = (124.7746 - 1.56375588   * k + 0.0020672  * T2 + 0.00000215 * T3).rad

        // Periodic corrections (identical set for New and Full Moon).
        let c = -0.40720 * sin(Mp)
              + 0.17241 * E * sin(M)
              + 0.01608 * sin(2 * Mp)
              + 0.01039 * sin(2 * F)
              + 0.00739 * E * sin(Mp - M)
              - 0.00514 * E * sin(Mp + M)
              + 0.00208 * E * E * sin(2 * M)
              - 0.00111 * sin(Mp - 2 * F)
              - 0.00057 * sin(Mp + 2 * F)
              + 0.00056 * E * sin(2 * Mp + M)
              - 0.00042 * sin(3 * Mp)
              + 0.00042 * E * sin(M + 2 * F)
              + 0.00038 * E * sin(M - 2 * F)
              - 0.00024 * E * sin(2 * Mp - M)
              - 0.00017 * sin(Om)
              - 0.00007 * sin(Mp + 2 * M)
              + 0.00004 * sin(2 * Mp - 2 * F)
              + 0.00004 * sin(3 * M)
              + 0.00003 * sin(Mp + M - 2 * F)
              + 0.00003 * sin(2 * Mp + 2 * F)
              - 0.00003 * sin(Mp + M + 2 * F)
              + 0.00003 * sin(Mp - M + 2 * F)
              - 0.00002 * sin(Mp - M - 2 * F)
              - 0.00002 * sin(3 * Mp + M)
              + 0.00002 * sin(4 * Mp)
        jde += c

        // Additional planetary corrections (the 14 A-terms).
        let a: [(Double, Double)] = [
            (0.000325, 299.77 + 0.107408 * k - 0.009173 * T2),
            (0.000165, 251.88 + 0.016321 * k),
            (0.000164, 251.83 + 26.651886 * k),
            (0.000126, 349.42 + 36.412478 * k),
            (0.000110, 84.66 + 18.206239 * k),
            (0.000062, 141.74 + 53.303771 * k),
            (0.000060, 207.14 + 2.453732 * k),
            (0.000056, 154.84 + 7.306860 * k),
            (0.000047, 34.52 + 27.261239 * k),
            (0.000042, 207.19 + 0.121824 * k),
            (0.000040, 291.34 + 1.844379 * k),
            (0.000037, 161.72 + 24.198154 * k),
            (0.000035, 239.56 + 25.513099 * k),
            (0.000023, 331.55 + 3.592518 * k),
        ]
        for (coeff, deg) in a { jde += coeff * sin(deg.rad) }

        let date = jdeToDate(jde)
        let isoFmt = ISO8601DateFormatter(); isoFmt.formatOptions = [.withFullDate]; isoFmt.timeZone = tz
        let timeFmt = DateFormatter(); timeFmt.timeZone = tz; timeFmt.dateFormat = "HH:mm"

        return MoonPhaseEvent(
            kind: kind,
            label: kind == .new ? "Luna nueva" : "Luna llena",
            emoji: kind == .new ? "🌑" : "🌕",
            datetime: date,
            date: isoFmt.string(from: date),
            timeLocal: timeFmt.string(from: date)
        )
    }

    private func jdeToDate(_ jde: Double) -> Date {
        Date(timeIntervalSince1970: (jde - 2440587.5) * 86400)
    }
}

private extension Double {
    var rad: Double { self * .pi / 180 }
}
