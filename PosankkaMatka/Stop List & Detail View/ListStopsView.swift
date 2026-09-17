//
//  ListStopsView.swift
//  PosankkaMatka
//
//  Created by sero on 25/2/26.
//

import SwiftUI
import FoliBusUI
import CoreLocation
import Forever

/// The home-sheet list (nearby stops + routes) with search and the distance
/// filter. Reads resource stores from the environment; HomeView owns the stack.
struct ListStopsView: View {
    @State var search = ""
    @Environment(ResourceStore<[Foli.Stop]>.self) private var stopsStore
    @Environment(ResourceStore<[Foli.Route]>.self) private var routesStore
    @Environment(LocationManager.self) var locationManager
    /// Nearby rows, recomputed only when an input changed (see `.task(id:)`).
    @State private var nearbyStops: [StopWithDistance] = []

    /// Authorization, read from observable state instead of calling into
    /// `CLLocationManager` from a `body`.
    private var isLocationAuthorized: Bool { locationManager.isAuthorized }
    /// Persisted distance filter (cheap to read in `body`; writes persist + publish).
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
                    nearbyStops: nearbyStops,
                    isLocationAuthorized: isLocationAuthorized,
                    searchFilter: $searchFilter,
                    selectedStopID: $selectedStopID,
                    selectedRoute: $selectedRoute
                )
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search stops or routes"))
                // Recompute off the body path, keyed on stop set + rounded
                // location + filter (sub-meter jitter ignored).
                .task(id: nearbyInputs(stops)) {
                    nearbyStops = nearbyRows(for: stops)
                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            }
        }
    }

    /// Nearby stops, nearest first. No location → empty (the list discloses why).
    private func nearbyRows(for stops: [Foli.Stop]) -> [StopWithDistance] {
        guard isLocationAuthorized, let coordinate = locationManager.currentLocation else { return [] }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let maxDistance: Double? = if case .proximity(let meters) = searchFilter, meters > 0 {
            meters
        } else {
            nil
        }
        return stops.nearest(to: origin, withinMeters: maxDistance)
            .map { StopWithDistance($0.stop, distance: $0.distance) }
    }

    /// Task identity for the nearby inputs; coordinates are rounded so sub-meter
    /// GPS jitter doesn't retrigger the recompute.
    private func nearbyInputs(_ stops: [Foli.Stop]) -> String {
        let coordinate = isLocationAuthorized ? locationManager.currentLocation : nil
        let latitude = coordinate.map { ($0.latitude * 100_000).rounded() } ?? 0
        let longitude = coordinate.map { ($0.longitude * 100_000).rounded() } ?? 0
        return "\(stops.count)|\(latitude)|\(longitude)|\(searchFilter)"
    }
}
