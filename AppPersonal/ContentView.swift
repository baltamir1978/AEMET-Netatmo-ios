import SwiftUI

struct ContentView: View {
    @ObservedObject private var cfg = AppConfiguration.shared
    // The app always opens on AEMET.
    @State private var selection = Tab.aemet
    // Bumped by a tides-widget tap so Sol·Luna scrolls to its Mareas card.
    @State private var tidesScrollSignal = 0

    private enum Tab: Hashable { case aemet, cosmos, actual, graficas, settings }

    var body: some View {
        TabView(selection: $selection) {
            AemetView()
                // Without an AEMET key the tab is served entirely from Open-Meteo, so
                // calling it "AEMET" would be misleading — show "Tiempo" in that mode.
                .tabItem { Label(cfg.isAemetConfigured ? "AEMET" : "Tiempo", systemImage: "cloud.sun") }
                .tag(Tab.aemet)
            CosmosView(scrollToTidesSignal: tidesScrollSignal)
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
        // Widget taps: open the matching tab (and scroll to Mareas for the tides widget).
        .onOpenURL { url in handleDeepLink(url) }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == WidgetDeepLink.scheme else { return }
        switch url.host {
        case WidgetDeepLink.aemet:
            selection = .aemet
        case WidgetDeepLink.netatmo:
            // The Actual tab only exists with Netatmo configured; fall back to AEMET otherwise.
            selection = cfg.isNetatmoConfigured ? .actual : .aemet
        case WidgetDeepLink.cosmos:
            selection = .cosmos
        case WidgetDeepLink.tides:
            selection = .cosmos
            tidesScrollSignal += 1   // ask Sol·Luna to scroll to its Mareas card
        default:
            break
        }
    }
}

#Preview {
    ContentView()
}
