//
//  SearchList.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import SwiftUI
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
        Group {
            if isListEmpty {
                emptyState
            } else {
                List {
                    if !stopRows.isEmpty {
                        Section(stopSectionTitle) {
                            ForEach(stopRows) { stopWithDistance in
                                Button {
                                    selectedStopID = stopWithDistance.stop.id
                                } label: {
                                    StopRow(stopWithDistance: stopWithDistance)
                                }
                                .tint(.primary)
                            }
                        }
                    }
                    if !routeRows.isEmpty {
                        Section("Routes") {
                            ForEach(routeRows) { route in
                                Button {
                                    selectedRoute = route
                                } label: {
                                    RouteRow(route: route)
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
            // The proximity filter only affects the nearby (idle) list and needs
            // a location to mean anything, so the control is shown only then.
            if showsFilterMenu {
                ToolbarItem(placement: .topBarTrailing) {
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
        }
    }

    // MARK: - Derived rows

    /// Stops for the current mode: nearby rows when idle, name/code matches when
    /// searching (no distances — proximity is irrelevant to a text search).
    private var stopRows: [StopWithDistance] {
        guard isSearching else { return nearbyStops }
        guard !search.isEmpty else { return [] }
        return stops
            .filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || ($0.code ?? "").localizedCaseInsensitiveContains(search)
            }
            .map { StopWithDistance($0) }
    }

    /// Routes for the current mode: all (line-sorted) when idle, matches when
    /// searching. Empty while search is active but the field is blank.
    private var routeRows: [Foli.Route] {
        let sorted = routes.sortedByLine()
        guard isSearching else { return sorted }
        guard !search.isEmpty else { return [] }
        return sorted.filter {
            $0.shortName.localizedCaseInsensitiveContains(search)
                || $0.longName.localizedCaseInsensitiveContains(search)
        }
    }

    private var isListEmpty: Bool { stopRows.isEmpty && routeRows.isEmpty }

    private var stopSectionTitle: String {
        (isSearching || !isLocationAuthorized) ? "Stops" : "Nearby Stops"
    }

    /// The proximity filter is meaningful only in the idle list with a location.
    private var showsFilterMenu: Bool { isLocationAuthorized && !isSearching }

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
}

// MARK: - Rows

private struct StopRow: View {
    let stopWithDistance: StopWithDistance

    var body: some View {
        HStack {
            Image(systemName: "signpost.right.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Text(stopWithDistance.stop.id).monospaced()
            Text(stopWithDistance.stop.name)
            Spacer()
            if let distanceText = stopWithDistance.distanceText {
                Text(distanceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RouteRow: View {
    let route: Foli.Route

    var body: some View {
        HStack(spacing: 12) {
            RouteBadge(route: route)
            Text(route.longName)
            Spacer()
        }
    }
}
