//
//  AppPersonalApp.swift
//  AppPersonal
//
//  Created by Bruno Altamirano on 25/05/2026.
//

import SwiftUI

@main
struct AppPersonalApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Cold launch: `scenePhase` never *changes* into `.active` here, so the
                // top-up has to be kicked off explicitly.
                .task { await BackgroundRefresher.refreshIfStale() }
        }
        // Background data refresh: SwiftUI registers the handler; we reschedule
        // it (at the cadence chosen in Ajustes) whenever the app goes to the
        // background. iOS decides exactly when it runs — the widgets self-fetch
        // as a backup so data still advances if the task is deferred.
        .backgroundTask(.appRefresh(BackgroundRefresher.taskIdentifier)) {
            await BackgroundRefresher.refreshAll()
            await BackgroundRefresher.schedule()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefresher.schedule()
                // Push whatever the app just saw onto the widgets. Without this, data the
                // app refreshed while you were using it only reached them on the widget's
                // own schedule — you'd close the app and still read the old temperature.
                WidgetStore.reload()
            case .active:
                Task { await BackgroundRefresher.refreshIfStale() }
            default:
                break
            }
        }
    }
}
