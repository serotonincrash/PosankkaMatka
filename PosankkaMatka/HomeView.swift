//
//  HomeView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import CoreLocation
import MapKit
import FoliBusUI
struct HomeView: View {
    @State var locationManager: LocationManager = LocationManager()
    
    @State var stop: StopWithDistance?
    var body: some View {
        TabView {
            Tab("Stops", systemImage: "house.and.flag") {
                // map? then link the 2 together using bindings on this view
                #warning("TODO add map")
                Group {
                    Map {
                        
                    }
                }
                .sheet(isPresented: .constant(true)) {
                    NavigationStack {
                        // do we have to calc everything here? abstract to shared view model??
                        // viewmodel/store for each resource?
                        ListStopsView()
                            .presentationDetents([.medium])
                        .navigationDestination(item: $stop) { stop in
                            StopView(stopWithDistance: stop)
                        }
                    }
                }
            }	
            Tab("Routes", systemImage: "map") {
                RouteView()
            }
        }
        .environment(locationManager)
    }
    
    
}

#Preview {
    HomeView()
}
