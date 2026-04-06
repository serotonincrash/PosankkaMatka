//
//  PosankkaMatkaApp.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import FoliBusAPI

@main
struct PosankkaMatkaApp: App {

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(
                    \.foliClientProvider,
                    DefaultFoliClientProvider(
                        configuration: FoliClientConfiguration(
                            cacheBehavior: .cachedOrFetch,
                            cacheTimeout: .default
                        )
                    )
                )
        }
    }
}
