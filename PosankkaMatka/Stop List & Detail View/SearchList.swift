//
//  SearchList.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import SwiftUI
import CoreLocation
import FoliBusUI
import Forever

/// The combined home-sheet list: "Nearby Stops" and "Routes" in one map-backed
/// sheet (à la Maps). Both idle and search states render sections for each type;
/// tapping a stop or a route sets the shared selection the map reacts to.
struct HomeSheetList: View {
    /// Max rows in the idle "Nearby Stops" section — the nearest this-many. The
    /// distance filter still applies; this bounds the row count so the list stays
    /// scannable rather than showing the whole network.
    private static let nearbyLimit = 25

    @Environment(\.isSearching) var isSearching
    @Environment(LocationManager.self) var locationManager

    @Binding var search: String
    let stops: [Foli.Stop]
    let routes: [Foli.Route]
    @Binding var searchFilter: SortState
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?

    var body: some View {
        // Idle: cap to the nearest `nearbyLimit`. Search results stay unbounded.
        let stopRows = isSearching ? searchedStops() : Array(filter(stops).prefix(Self.nearbyLimit))
        let routeRows = filteredRoutes()

        Group {
            if stopRows.isEmpty && routeRows.isEmpty {
                emptyState
            } else {
                List {
                    if !stopRows.isEmpty {
                        Section(isSearching ? "Stops" : "Nearby Stops") {
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
                        }
                    }
                    if !routeRows.isEmpty {
                        Section("Routes") {
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
                        }
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

    /// Nearby stops (idle state): distance-filtered and sorted per `searchFilter`.
    func filter(_ stops: [Foli.Stop]) -> [StopWithDistance] {
        var sortedStops = stops.sorted { s1, s2 in
            (Int(s1.id) ?? 0) < (Int(s2.id) ?? 0)
        }

        if locationManager.checkLocationAuthorization() {
            guard let location = locationManager.currentLocation, let currCLLocation = CLLocation(location) else {
                return sortedStops.map { .init($0) }
            }
            if case .proximity(let distance) = searchFilter, distance > 0 {
                sortedStops = sortedStops.filter(byDistance: distance, from: currCLLocation)
            }
            sortedStops = sortedStops.sortedByDistance(to: currCLLocation)
            return sortedStops.map {
                if let stopLocation = $0.location, let stopCoord = CLLocation(stopLocation.toCLCoordinate()) {
                    StopWithDistance($0, distance: currCLLocation.distance(from: stopCoord))
                } else {
                    StopWithDistance($0)
                }
            }
        } else {
            return sortedStops.map { StopWithDistance($0) }
        }
    }
}
