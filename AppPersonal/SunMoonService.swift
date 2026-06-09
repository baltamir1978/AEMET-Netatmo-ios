import Foundation

// MARK: - Result types

struct SunMoonResult {
    struct LocationInfo { let key: String; let name: String; let lat: Double; let lon: Double }
    struct SunInfo { let sunrise: String?; let noon: String?; let sunset: String?; let daylight: String? }
    struct MoonInfo { let moonrise: String?; let moonset: String?; let phase: String; let emoji: String; let illumination: Double }
    let location: LocationInfo
    let date: String
    let sun: SunInfo
    let moon: MoonInfo
}

// MARK: - Predefined locations

struct SunMoonLocation: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let lat: Double
    let lon: Double
    let elevation: Double
    let tz: String
}

let sunMoonLocations: [SunMoonLocation] = [
    SunMoonLocation(key: "lagranja", name: "La Granja",  lat: 40.9000, lon: -4.0167, elevation: 1191, tz: "Europe/Madrid"),
    SunMoonLocation(key: "madrid",   name: "Madrid",     lat: 40.4168, lon: -3.7038, elevation: 667,  tz: "Europe/Madrid"),
    SunMoonLocation(key: "llanes",   name: "Llanes",     lat: 43.4214, lon: -4.7546, elevation: 5,    tz: "Europe/Madrid"),
]

// MARK: - Service

struct SunMoonService {
    static let shared = SunMoonService()

    func calculate(location: SunMoonLocation, date: Date) -> SunMoonResult {
        let tz = TimeZone(identifier: location.tz) ?? .current

        let sun  = sunTimes(date: date, lat: location.lat, lon: location.lon, tz: tz)
        let moon = moonInfo(date: date, lat: location.lat, lon: location.lon, tz: tz)

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        isoFmt.timeZone = tz

        return SunMoonResult(
            location: .init(key: location.key, name: location.name, lat: location.lat, lon: location.lon),
            date: isoFmt.string(from: date),
            sun: .init(sunrise:  sun.sunrise.map  { hhmm($0, tz: tz) },
                       noon:     sun.noon.map     { hhmm($0, tz: tz) },
                       sunset:   sun.sunset.map   { hhmm($0, tz: tz) },
                       daylight: sun.daylight),
            moon: .init(moonrise:     moon.rise.map     { hhmm($0, tz: tz) },
                        moonset:      moon.set.map      { hhmm($0, tz: tz) },
                        phase:        moon.phaseName,
                        emoji:        moon.phaseEmoji,
                        illumination: moon.illumination)
        )
    }

    private func hhmm(_ date: Date, tz: TimeZone) -> String {
        let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Sun calculations (NOAA / Meeus algorithm)
    // Accurate to ~1 min between 72°N and 72°S

    private struct SunTimes {
        var sunrise: Date?; var noon: Date?; var sunset: Date?; var daylight: String?
    }

    private func sunTimes(date: Date, lat: Double, lon: Double, tz: TimeZone) -> SunTimes {
        let jd = julianDay(date: date)

        // Julian centuries since J2000.0
        let T = (jd - 2451545.0) / 36525.0

        // Geometric mean longitude of the sun (degrees)
        let L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)).truncatingRemainder(dividingBy: 360)

        // Mean anomaly of the sun (degrees)
        let M = (357.52911 + T * (35999.05029 - 0.0001537 * T)).truncatingRemainder(dividingBy: 360)
        let Mrad = M.radians

        // Equation of center
        let C = sin(Mrad) * (1.914602 - T * (0.004817 + 0.000014 * T))
               + sin(2 * Mrad) * (0.019993 - 0.000101 * T)
               + sin(3 * Mrad) * 0.000289

        // Sun's true longitude
        let sunLon = L0 + C

        // Apparent longitude (corrected for aberration and nutation)
        let omega = 125.04 - 1934.136 * T
        let lambda = sunLon - 0.00569 - 0.00478 * sin(omega.radians)

        // Obliquity of ecliptic
        let epsilon0 = 23.0 + (26.0 + (21.448 - T * (46.8150 + T * (0.00059 - T * 0.001813))) / 60.0) / 60.0
        let epsilon  = epsilon0 + 0.00256 * cos(omega.radians)

        // Right ascension
        let sinLambda = sin(lambda.radians)
        let _ = atan2(cos(epsilon.radians) * sinLambda, cos(lambda.radians)).degrees

        // Declination
        let sinDec = sin(epsilon.radians) * sinLambda
        let decRad = asin(sinDec)

        // Equation of time (minutes)
        let eqT = equationOfTime(T: T, L0: L0, M: M, epsilon: epsilon)

        // Solar noon (fractional day UT)
        let solarNoonUT = (720 - 4 * lon - eqT) / 1440.0   // fraction of day in UT

        // Hour angle for sunrise/sunset (zenith = 90.833° accounts for refraction + solar disc)
        let zenith = 90.833.radians
        let latRad = lat.radians
        let cosHA = (cos(zenith) - sin(latRad) * sinDec) / (cos(latRad) * cos(decRad))

        var result = SunTimes()

        if cosHA.isNaN || cosHA > 1 {
            // Polar night
        } else if cosHA < -1 {
            // Midnight sun
        } else {
            let HA = acos(cosHA).degrees   // hour angle in degrees
            let sunriseUT  = solarNoonUT - HA / 360.0
            let sunsetUT   = solarNoonUT + HA / 360.0

            let cal = Calendar(identifier: .gregorian)
            var comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
            comps.hour = 0; comps.minute = 0; comps.second = 0
            if let midnight = cal.date(from: comps) {
                result.sunrise = midnight.addingTimeInterval(sunriseUT * 86400)
                result.sunset  = midnight.addingTimeInterval(sunsetUT  * 86400)
                result.noon    = midnight.addingTimeInterval(solarNoonUT * 86400)
                if let rise = result.sunrise, let set = result.sunset, set > rise {
                    let secs = Int(set.timeIntervalSince(rise))
                    result.daylight = String(format: "%dh %02dm", secs / 3600, (secs % 3600) / 60)
                }
            }
        }

        return result
    }

    private func equationOfTime(T: Double, L0: Double, M: Double, epsilon: Double) -> Double {
        let y = tan(epsilon.radians / 2); let y2 = y * y
        let L0r = L0.radians; let Mr = M.radians
        let eqT = y2 * sin(2 * L0r)
                 - 2 * 0.016708634 * sin(Mr)
                 + 4 * 0.016708634 * y2 * sin(Mr) * cos(2 * L0r)
                 - 0.5 * y2 * y2 * sin(4 * L0r)
                 - 1.25 * 0.016708634 * 0.016708634 * sin(2 * Mr)
        return 4 * eqT.degrees  // in minutes
    }

    // MARK: - Moon calculations

    private struct MoonCalc {
        var rise: Date?; var set: Date?
        var phaseName: String; var phaseEmoji: String; var illumination: Double
    }

    private func moonInfo(date: Date, lat: Double, lon: Double, tz: TimeZone) -> MoonCalc {
        // Moon phase based on known new moon epoch
        // Reference new moon: 2000-01-06 18:14 UTC (JD 2451550.259)
        let refNewMoonJD = 2451550.259
        let synodicMonth = 29.530588853
        let jd = julianDay(date: date)
        let daysSinceRef = jd - refNewMoonJD
        var phase = daysSinceRef.truncatingRemainder(dividingBy: synodicMonth)
        if phase < 0 { phase += synodicMonth }

        let illumination = round(50 * (1 - cos(2 * .pi * phase / synodicMonth)) / 2 * 10) / 10

        let (phaseName, phaseEmoji) = moonPhaseName(phase)

        // Simplified moonrise/moonset via successive approximation
        let (rise, set) = moonRiseSet(date: date, lat: lat, lon: lon, tz: tz)

        return MoonCalc(rise: rise, set: set, phaseName: phaseName, phaseEmoji: phaseEmoji, illumination: illumination)
    }

    private func moonPhaseName(_ phase: Double) -> (String, String) {
        switch phase {
        case ..<1.85:  return ("Luna nueva",           "🌑")
        case ..<5.54:  return ("Creciente iluminante", "🌒")
        case ..<9.23:  return ("Cuarto creciente",     "🌓")
        case ..<12.92: return ("Gibosa creciente",     "🌔")
        case ..<16.61: return ("Luna llena",           "🌕")
        case ..<20.30: return ("Gibosa menguante",     "🌖")
        case ..<23.99: return ("Cuarto menguante",     "🌗")
        case ..<27.68: return ("Menguante iluminante", "🌘")
        default:       return ("Luna nueva",           "🌑")
        }
    }

    /// Simplified moonrise/moonset using the moon's approximate hourly motion.
    /// Accurate to ~15 min for mid-latitudes.
    private func moonRiseSet(date: Date, lat: Double, lon: Double, tz: TimeZone) -> (Date?, Date?) {
        let cal = Calendar(identifier: .gregorian)
        var tzComps = cal.dateComponents(in: tz, from: date)
        tzComps.hour = 0; tzComps.minute = 0; tzComps.second = 0
        guard let midnight = cal.date(from: tzComps) else { return (nil, nil) }

        var riseTime: Date? = nil
        var setTime:  Date? = nil
        var prevAlt = moonAltitude(at: midnight, lat: lat, lon: lon)

        for h in 1...24 {
            let t = midnight.addingTimeInterval(Double(h) * 3600)
            let alt = moonAltitude(at: t, lat: lat, lon: lon)
            if prevAlt < 0 && alt >= 0 && riseTime == nil {
                // Interpolate
                let frac = -prevAlt / (alt - prevAlt)
                riseTime = midnight.addingTimeInterval((Double(h) - 1 + frac) * 3600)
            }
            if prevAlt >= 0 && alt < 0 && setTime == nil {
                let frac = prevAlt / (prevAlt - alt)
                setTime = midnight.addingTimeInterval((Double(h) - 1 + frac) * 3600)
            }
            prevAlt = alt
        }
        return (riseTime, setTime)
    }

    /// Moon altitude above horizon at a given instant (degrees), simplified.
    private func moonAltitude(at date: Date, lat: Double, lon: Double) -> Double {
        let jd = julianDay(date: date)
        let T = (jd - 2451545.0) / 36525.0

        // Moon's mean longitude and anomaly (Meeus simplified, ch. 47)
        let L = (218.3164477 + 481267.88123421 * T).truncatingRemainder(dividingBy: 360)
        let D = (297.8501921 + 445267.1114034  * T).truncatingRemainder(dividingBy: 360)
        let M = (357.5291092 + 35999.0502909   * T).truncatingRemainder(dividingBy: 360)
        let Mp = (134.9633964 + 477198.8675055  * T).truncatingRemainder(dividingBy: 360)
        let F = (93.2720950  + 483202.0175233  * T).truncatingRemainder(dividingBy: 360)

        // Longitude corrections (major terms only)
        var dL = 6288774 * sin(Mp.radians)
                 + 1274027 * sin((2*D - Mp).radians)
                 + 658314  * sin((2*D).radians)
                 - 185116  * sin(M.radians)
                 - 114332  * sin((2*F).radians)
        dL /= 1_000_000.0   // in degrees

        // Latitude (b)
        var dB = 5128122 * sin(F.radians)
                 + 280602 * sin((Mp + F).radians)
                 + 277693 * sin((Mp - F).radians)
        dB /= 1_000_000.0

        let moonLon = (L + dL).truncatingRemainder(dividingBy: 360)
        let moonLat = dB

        // Obliquity of ecliptic
        let eps = 23.4393 - 0.0000004 * T

        // Convert ecliptic → equatorial
        let decRad = asin(sin(moonLat.radians) * cos(eps.radians)
                         + cos(moonLat.radians) * sin(eps.radians) * sin(moonLon.radians))
        let raRad  = atan2(sin(moonLon.radians) * cos(eps.radians) - tan(moonLat.radians) * sin(eps.radians),
                           cos(moonLon.radians))

        // Greenwich Mean Sidereal Time
        let gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0)).truncatingRemainder(dividingBy: 360)

        // Local hour angle
        let lha = (gmst + lon - raRad.degrees).truncatingRemainder(dividingBy: 360)

        // Altitude
        let sinAlt = sin(lat.radians) * sin(decRad)
                   + cos(lat.radians) * cos(decRad) * cos(lha.radians)
        return asin(sinAlt).degrees
    }

    // MARK: - Julian Day Number

    func julianDay(date: Date) -> Double {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        var Y = Double(comps.year!)
        var M = Double(comps.month!)
        let D = Double(comps.day!) + Double(comps.hour ?? 0) / 24.0
                + Double(comps.minute ?? 0) / 1440.0 + Double(comps.second ?? 0) / 86400.0
        if M <= 2 { Y -= 1; M += 12 }
        let A = floor(Y / 100)
        let B = 2 - A + floor(A / 4)
        return floor(365.25 * (Y + 4716)) + floor(30.6001 * (M + 1)) + D + B - 1524.5
    }
}

// MARK: - Degree/radian helpers
private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
