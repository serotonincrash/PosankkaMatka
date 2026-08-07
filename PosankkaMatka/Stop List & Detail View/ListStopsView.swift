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
    /// Max rows in the idle "Nearby Stops" section.
    private static let nearbyLimit = 25

    @State var search = ""
    @Environment(ResourceStore<[Foli.Stop]>.self) private var stopsStore
    @Environment(ResourceStore<[Foli.Route]>.self) private var routesStore
    @Environment(LocationManager.self) var locationManager
    /// Owns the nearby-stop computation so it happens on input changes, not in `body`.
    @State private var nearbyStops = NearbyStopsProvider()

    /// Authorization, read from observable state instead of calling into
    /// `CLLocationManager` from a `body`.
    private var isLocationAuthorized: Bool { locationManager.isAuthorized }
    /// Persisted distance filter. `Forever` is backed by an in-memory
    /// `@Observable` store, so reading this in `body` is cheap and registers
    /// correct change tracking; writes funnel through `set` (persist + publish).
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
                    search: search,
                    stops: stops,
                    routes: routesStore.state.value ?? [],
                    nearbyStops: nearbyStops.rows,
                    isLocationAuthorized: isLocationAuthorized,
                    searchFilter: $searchFilter,
                    selectedStopID: $selectedStopID,
                    selectedRoute: $selectedRoute
                )
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search stops or routes"))
                // Recompute off the `body` path. Keyed on the stop set, the
                // rounded location (sub-meter jitter is ignored), and the filter,
                // so the provider only reruns when an input actually changed.
                .task(id: nearbyInputs(stops)) {
                    nearbyStops.recompute(
                        stops: stops,
                        coordinate: isLocationAuthorized ? locationManager.currentLocation : nil,
                        filter: searchFilter,
                        limit: Self.nearbyLimit
                    )
                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            }
        }
    }

    /// Identity of the inputs to the nearby computation. Coordinates are rounded
    /// so sub-meter GPS jitter doesn't retrigger the recompute; the filter is
    /// included so a change re-runs the task.
    private func nearbyInputs(_ stops: [Foli.Stop]) -> String {
        let coordinate = isLocationAuthorized ? locationManager.currentLocation : nil
        let latitude = coordinate.map { ($0.latitude * 100_000).rounded() } ?? 0
        let longitude = coordinate.map { ($0.longitude * 100_000).rounded() } ?? 0
        return "\(stops.count)|\(latitude)|\(longitude)|\(searchFilter)"
    }
}
