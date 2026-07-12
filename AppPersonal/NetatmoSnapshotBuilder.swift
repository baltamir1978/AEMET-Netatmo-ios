import Foundation

/// Builds the widget-facing `NetatmoSnapshot` from the raw Netatmo device + modules.
///
/// Single source of truth on purpose: the Actual tab and the background refresh both write
/// this snapshot, and when they filled it differently the widgets silently disagreed with
/// the app (exactly how the AEMET current temperature regressed).
enum NetatmoSnapshotBuilder {

    /// `dashboard_data` keys, per Netatmo's Weather API.
    static func make(station: NetatmoDevice,
                     exterior: NetatmoModule?,
                     rain: NetatmoModule?,
                     name: String,
                     lat: Double?,
                     lon: Double?) -> NetatmoSnapshot {
        let indoor = station.dashboardData
        let out = exterior?.dashboardData
        let rainData = rain?.dashboardData

        return NetatmoSnapshot(
            stationName: name,
            temperature: out?["Temperature"]?.doubleValue,
            humidity: out?["Humidity"]?.doubleValue,
            // Pressure is reported by the base station, but it belongs to the outdoor set.
            pressure: indoor?["Pressure"]?.doubleValue ?? out?["Pressure"]?.doubleValue,
            date: Date(),
            lat: lat,
            lon: lon,
            tempMinOut: out?["min_temp"]?.doubleValue,
            tempMaxOut: out?["max_temp"]?.doubleValue,
            rain: rainData?["Rain"]?.doubleValue,
            rainToday: rainData?["sum_rain_24"]?.doubleValue,
            tempIn: indoor?["Temperature"]?.doubleValue,
            humidityIn: indoor?["Humidity"]?.doubleValue,
            co2: indoor?["CO2"]?.doubleValue,
            noise: indoor?["Noise"]?.doubleValue
        )
    }
}
