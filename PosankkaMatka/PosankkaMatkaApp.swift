//
//  PosankkaMatkaApp.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import FoliBusUI

@main
struct PosankkaMatkaApp: App {
    @State private var model = AppModel(
        client: DefaultFoliClientProvider(
            configuration: FoliClientConfiguration(cacheBehavior: .cachedOrFetch, cacheTTL: .default)
        ).client()
    )

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                // A geofence hit can relaunch the app; reattach before it's delivered.
                .task { await model.stopAlert.resume() }
        }
    }
}
