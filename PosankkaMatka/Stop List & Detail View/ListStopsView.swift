//
//  ContentView.swift
//  FoliAPITestApp
//
//  Created by sero on 25/2/26.
//

import SwiftUI
import FoliBusUI
import CoreLocation
import Forever

/// Hosts the combined home-sheet list (nearby stops + routes) with search and the
/// distance filter. Reads both resource stores from the environment; it has no
/// NavigationStack of its own — HomeView owns the stack and destinations.
struct ListStopsView: View {
    @State var search = ""
    @Environment(ResourceStore<[Foli.Stop]>.self) private var stopsStore
    @Environment(ResourceStore<[Foli.Route]>.self) private var routesStore
    @Environment(LocationManager.self) var locationManager
    @Forever("nearbySearchFilter") var searchFilter: SortState = .proximity(2000)

    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?

    var body: some View {
        Group {
            switch stopsStore.state {
            case .loading:
                ProgressView()
            case .success(let stops):
                HomeSheetList(
                    search: $search,
                    stops: stops,
                    routes: routesStore.state.value ?? [],
                    searchFilter: $searchFilter,
                    selectedStopID: $selectedStopID,
                    selectedRoute: $selectedRoute
                )
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search stops or routes"))
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            }
        }
    }
}
