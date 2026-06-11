import SwiftUI

struct ContentView: View {
    @ObservedObject private var cfg = AppConfiguration.shared
    // The app always opens on AEMET.
    @State private var selection = Tab.aemet

    private enum Tab: Hashable { case aemet, cosmos, actual, graficas, settings }

    var body: some View {
        TabView(selection: $selection) {
            AemetView()
                .tabItem { Label("AEMET",     systemImage: "cloud.sun") }
                .tag(Tab.aemet)
            CosmosView()
                .tabItem { Label("Sol·Luna",  systemImage: "moon.stars") }
                .tag(Tab.cosmos)
            // Netatmo-dependent tabs only show once credentials are configured,
            // and sit at the end of the bar.
            if cfg.isNetatmoConfigured {
                ActualView()
                    .tabItem { Label("Actual",    systemImage: "thermometer.medium") }
                    .tag(Tab.actual)
                GraficasView()
                    .tabItem { Label("Gráficas",  systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(Tab.graficas)
            }
            SettingsView()
                .tabItem { Label("Ajustes",   systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // Fill in the station/module IDs automatically once credentials exist.
        .task {
            if cfg.deviceId.isEmpty { await cfg.autoDetectStation() }
        }
    }
}

#Preview {
    ContentView()
}
