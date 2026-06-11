import WidgetKit
import SwiftUI

@main
struct AppPersonalWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeatherWidget()
        SunMoonWidget()
        TidesWidget()
    }
}
