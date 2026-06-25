import Foundation

/// Builds the widget-facing `AemetSnapshot` from raw AEMET forecast roots.
/// Lives in the shared layer (app + widget targets) so the widget extension can
/// fetch AEMET data itself and produce the same snapshot the app writes.
enum AemetSnapshotBuilder {

    /// True when the forecast day's date falls before today (AEMET occasionally
    /// includes "ayer" at the head of the daily array).
    static func isPastDay(_ fecha: String?) -> Bool {
        guard let fecha else { return false }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        guard let date = f.date(from: String(fecha.prefix(10))) else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    /// The daily forecast with any past days ("ayer") dropped, so index 0 is today.
    static func upcomingDays(_ root: AemetDailyRoot?) -> [AemetDailyDay] {
        (root?.prediccion?.dia ?? []).filter { !isPastDay($0.fecha) }
    }

    static func makeAemetSnapshot(municipio: String,
                                  daily: AemetDailyRoot?,
                                  hourly: AemetHourlyRoot?,
                                  alert: AemetAlertBadge? = nil) -> AemetSnapshot {
        let today = upcomingDays(daily).first
        let hourlyDay = hourly?.prediccion?.dia?.first
        let nowHour = Calendar.current.component(.hour, from: Date())
        let skyCode = hourlyDay?.estadoCielo?.first(where: { Int($0.periodo ?? "") == nowHour })?.value
            ?? hourlyDay?.estadoCielo?.first?.value
        let skyDesc = hourlyDay?.estadoCielo?.first(where: { Int($0.periodo ?? "") == nowHour })?.descripcion
            ?? hourlyDay?.estadoCielo?.first?.descripcion ?? "—"
        let hourPts = hourPoints(from: hourly)
        // Big-number temp: the forecast for the current hour, falling back to the first
        // upcoming hour. AEMET sometimes prunes the current (partial) hour from dia[0],
        // which left the exact-hour match nil and the widget showing "—".
        let currentTemp: Int? = hourlyDay?.temperatura?
            .first(where: { Int($0.periodo ?? "") == nowHour })?
            .value.flatMap { Double($0) }.map { Int($0.rounded()) }
            ?? hourPts.first?.temp

        let isoFmt = ISO8601DateFormatter(); isoFmt.formatOptions = [.withFullDate]
        let dayPoints: [AemetDayPoint] = upcomingDays(daily).prefix(6).compactMap { day in
            guard let date = isoFmt.date(from: String((day.fecha ?? "").prefix(10))) else { return nil }
            return AemetDayPoint(
                date: date,
                tempMin: day.temperatura?.minima.map { Int($0.rounded()) },
                tempMax: day.temperatura?.maxima.map { Int($0.rounded()) },
                skyCode: dayPickPeriod(day.estadoCielo)?.value,
                prob: dayMaxValue(day.probPrecipitacion)?.value.flatMap { Int($0) }
            )
        }

        return AemetSnapshot(
            municipio: municipio,
            tempMin: today?.temperatura?.minima.map { Int($0.rounded()) },
            tempMax: today?.temperatura?.maxima.map { Int($0.rounded()) },
            currentTemp: currentTemp,
            skyDescription: skyDesc,
            skyCode: skyCode,
            date: Date(),
            hourly: hourPts.isEmpty ? nil : hourPts,
            daily: dayPoints.isEmpty ? nil : dayPoints,
            alert: alert
        )
    }

    /// Next ~8 hours (within 48h) from an hourly root, for the widget strip.
    static func hourPoints(from hourly: AemetHourlyRoot?) -> [AemetHourPoint] {
        let days = hourly?.prediccion?.dia ?? []
        let now = Date(); let cal = Calendar.current
        let isoFmt = ISO8601DateFormatter(); isoFmt.formatOptions = [.withFullDate]
        let nowFloor = cal.date(bySettingHour: cal.component(.hour, from: now), minute: 0, second: 0, of: now)!
        let cutoff = now.addingTimeInterval(48 * 3600)
        var result: [AemetHourPoint] = []
        for day in days {
            let dayStr = String((day.fecha ?? "").prefix(10))
            guard let dayDate = isoFmt.date(from: dayStr) else { continue }
            for tEntry in (day.temperatura ?? []) {
                guard let hour = Int(tEntry.periodo ?? ""),
                      let temp = Double(tEntry.value ?? ""),
                      let entryDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: dayDate),
                      entryDate >= nowFloor && entryDate <= cutoff else { continue }
                let sky = day.estadoCielo?.first(where: { Int($0.periodo ?? "") == hour })?.value
                let probStr = day.probPrecipitacion?.first(where: { p in
                    guard let per = p.periodo, per.count == 4 else { return false }
                    let s = Int(per.prefix(2)) ?? 0; let e = Int(per.suffix(2)) ?? 0
                    return hour >= s && hour < e
                })?.value
                result.append(AemetHourPoint(hour: hour, temp: Int(temp.rounded()), skyCode: sky,
                                             prob: probStr.flatMap { Int($0) },
                                             isToday: cal.isDateInToday(dayDate)))
            }
        }
        return Array(result.prefix(8))
    }

    /// Static twins of the instance `pickPeriod` / `maxOfDay` helpers.
    static func dayPickPeriod(_ arr: [AemetPeriodValue]?) -> AemetPeriodValue? {
        guard let arr else { return nil }
        for p in ["00-24", "12-24", "06-24"] {
            if let m = arr.first(where: { $0.periodo == p && ($0.value ?? "").isEmpty == false }) { return m }
        }
        return arr.first(where: { ($0.value ?? "").isEmpty == false }) ?? arr.first
    }

    static func dayMaxValue(_ arr: [AemetPeriodValue]?) -> AemetPeriodValue? {
        arr?.max(by: { (Double($0.value ?? "") ?? 0) < (Double($1.value ?? "") ?? 0) })
    }
}
