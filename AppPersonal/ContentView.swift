import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ActualView()
                .tabItem { Label("Actual",    systemImage: "thermometer.medium") }
            GraficasView()
                .tabItem { Label("Gráficas",  systemImage: "chart.line.uptrend.xyaxis") }
            CosmosView()
                .tabItem { Label("Sol·Luna",  systemImage: "moon.stars") }
            AemetView()
                .tabItem { Label("AEMET",     systemImage: "cloud.sun") }
            SettingsView()
                .tabItem { Label("Ajustes",   systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
}
