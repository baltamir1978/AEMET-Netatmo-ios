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
            if phase == .background { BackgroundRefresher.schedule() }
        }
    }
}
