//
//  SearchList.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import SwiftUI
import CoreLocation
import FoliBusUI

/// The combined home-sheet list: "Nearby Stops" and "Routes" in one map-backed
/// sheet (à la Maps). Both idle and search states render sections for each type;
/// tapping a stop or a route sets the shared selection the map reacts to.
struct HomeSheetList: View {
    @Environment(\.isSearching) var isSearching

    /// Current search text. Read-only here — `.searchable` on the parent owns the write.
    let search: String
    let stops: [Foli.Stop]
    let routes: [Foli.Route]
    /// Precomputed nearby rows (see `NearbyStopsProvider`). Passed in rather than
    /// derived here so `body` stays pure rendering.
    let nearbyStops: [StopWithDistance]
    /// Whether location is authorized — resolved once by the parent instead of
    /// calling into `LocationManager` from `body`.
    let isLocationAuthorized: Bool
    /// Distance filter, bound to the persisted `@Forever` value in the parent.
    @Binding var searchFilter: SortState
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?

    var body: some View {
        // Search results stay unbounded; the idle list arrives pre-trimmed.
        let stopRows = isSearching ? searchedStops() : nearbyStops
        let routeRows = filteredRoutes()

        Group {
            List {
                Section((isSearching || !isLocationAuthorized) ? "Stops" : "Nearby Stops") {
                    if !stopRows.isEmpty {
                        ForEach(stopRows) { stopWithDistance in
                            Button { selectedStopID = stopWithDistance.stop.id } label: {
                                HStack {
                                    Image(systemName: "signpost.right.fill")
                                        .foregroundStyle(.secondary)
                                        .imageScale(.small)
                                    Text(stopWithDistance.stop.id).monospaced()
                                    Text(stopWithDistance.stop.name)
                                    Spacer()
                                    if let distance = stopWithDistance.distance {
                                        Text(distance < 1000 ? "\(Int(distance)) m" : "\((distance / 1000).formatted(toDecimalPlaces: 2)) km")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    } else {
                        emptyState
                    }
                }
                Section("Routes") {
                    if !routeRows.isEmpty {
                        
                        ForEach(routeRows) { route in
                            Button { selectedRoute = route } label: {
                                HStack(spacing: 12) {
                                    RouteBadge(route: route)
                                    Text(route.longName)
                                    Spacer()
                                }
                            }
                            .tint(.primary)
                        }
                    } else {
                        emptyState
                    }
                }
            }
        
        }
        .navigationTitle(Text("Föli"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button {
                    searchFilter = .none
                } label: {
                    if searchFilter == .none {
                        Image(systemName: "checkmark").imageScale(.small)
                    }
                    Label("None", systemImage: "location.slash")
                }
                Section("Distance") {
                    Picker(selection: $searchFilter) {
                        Text("500 m").tag(SortState.proximity(500))
                        Text("1 km").tag(SortState.proximity(1000))
                        Text("2 km").tag(SortState.proximity(2000))
                    } label: {
                        Label("Filter by Proximity", systemImage: "location")
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if isSearching && search.isEmpty {
            ContentUnavailableView("Start typing", systemImage: "magnifyingglass", description: Text("Search for a stop or route by name or number."))
        } else if isSearching {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView("Nothing to show", systemImage: "bus", description: Text("No stops or routes are available."))
        }
    }

    // MARK: - Filtering

    /// Routes filtered by the current search (number or name), numeric-sorted.
    private func filteredRoutes() -> [Foli.Route] {
        let sorted = routes.sortedByLine()
        guard isSearching, !search.isEmpty else { return isSearching ? [] : sorted }
        return sorted.filter {
            $0.shortName.localizedCaseInsensitiveContains(search)
                || $0.longName.localizedCaseInsensitiveContains(search)
        }
    }

    /// Stops matching the search text (name or code).
    private func searchedStops() -> [StopWithDistance] {
        guard !search.isEmpty else { return [] }
        let matches = stops.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || ($0.code ?? "").localizedCaseInsensitiveContains(search)
        }
        return matches.map { StopWithDistance($0) }
    }

}
