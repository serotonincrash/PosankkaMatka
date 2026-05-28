//
//  HomeView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import CoreLocation
struct HomeView: View {
    @State var locationManager: LocationManager = LocationManager()
    var body: some View {
        TabView {
            Tab("Stops", systemImage: "house.and.flag") {
                // map? then link the 2 together using bindings on this view
                ListStopsView()
            }
        }
        .environment(locationManager)
    }
}

#Preview {
    HomeView()
}
