//
//  HomeSheetList.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import SwiftUI
import UIKit
import FoliBusUI

/// The home-sheet list: "Nearby Stops" and "Routes". Tapping a row sets the shared
/// selection the map reacts to.
struct HomeSheetList: View {
    @Environment(\.isSearching) var isSearching

    /// Search text (read-only; `.searchable` owns the write).
    let search: String
    let stops: [Foli.Stop]
    let routes: [Foli.Route]
    /// Precomputed nearby rows; empty cases are disclosed by `stopsDisclosure`.
    let nearbyStops: [StopWithDistance]
    /// Whether location is authorized (resolved by the parent).
    let isLocationAuthorized: Bool
    /// Distance filter, bound to the persisted `@Forever` value in the parent.
    @Binding var searchFilter: SortState
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?

    /// Idle "Nearby Stops" rows shown before the "Show all stops" disclosure.
    private static let nearbyLimit = 25
    @State private var showsAllNearbyStops = false

    var body: some View {
        Group {
            if isListEmpty {
                emptyState
            } else {
                List {
                    if showsStopsSection {
                        Section(stopSectionTitle) {
                            if stopRows.isEmpty {
                                stopsDisclosure
                            } else {
                                ForEach(visibleStopRows) { stopWithDistance in
                                    Button {
                                        selectedStopID = stopWithDistance.stop.id
                                    } label: {
                                        StopRow(stopWithDistance: stopWithDistance)
                                    }
                                    .tint(.primary)
                                }
                                if showsNearbyDisclosure {
                                    Button("Show all \(stopRows.count) stops") {
                                        showsAllNearbyStops = true
                                    }
                                }
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
        // A filter change re-scopes the list; collapse any expansion.
        .onChange(of: searchFilter) { _, _ in
            showsAllNearbyStops = false
        }
        .toolbar {
            if showsFilterMenu {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Buttons, not a `Picker`: a Picker in a Menu nests as
                        // a submenu, hiding the options.
                        Section("Show stops within") {
                            distanceOption("Any distance", systemImage: "infinity", filter: .none)
                            distanceOption("500 m", systemImage: "location", filter: .proximity(500))
                            distanceOption("1 km", systemImage: "location", filter: .proximity(1000))
                            distanceOption("2 km", systemImage: "location", filter: .proximity(2000))
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    // MARK: - Derived rows

    /// Nearby rows when idle, name/code matches when searching.
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

    /// Rendered rows: nearby is capped at `nearbyLimit` until expanded; search is uncapped.
    private var visibleStopRows: [StopWithDistance] {
        guard !isSearching else { return stopRows }
        return showsAllNearbyStops ? stopRows : Array(stopRows.prefix(Self.nearbyLimit))
    }

    /// True when the idle list has more than the cap and isn't expanded.
    private var showsNearbyDisclosure: Bool {
        !isSearching && !showsAllNearbyStops && stopRows.count > Self.nearbyLimit
    }

    /// All (line-sorted) routes when idle, matches when searching.
    private var routeRows: [Foli.Route] {
        let sorted = routes.sortedByLine()
        guard isSearching else { return sorted }
        guard !search.isEmpty else { return [] }
        return sorted.filter {
            $0.shortName.localizedCaseInsensitiveContains(search)
                || $0.longName.localizedCaseInsensitiveContains(search)
        }
    }

    /// Full-sheet empty state fires only for a search with no matches; idle always
    /// renders the list.
    private var isListEmpty: Bool { isSearching && stopRows.isEmpty && routeRows.isEmpty }

    /// Search shows the stops section only with matches; idle always shows it.
    private var showsStopsSection: Bool { isSearching ? !stopRows.isEmpty : true }

    private var stopSectionTitle: String { isSearching ? "Stops" : "Nearby Stops" }

    /// The proximity filter is meaningful only in the idle list with a location.
    private var showsFilterMenu: Bool { isLocationAuthorized && !isSearching }

    // MARK: - Empty / disclosure states

    /// Full-sheet empty state (see `isListEmpty`).
    @ViewBuilder
    private var emptyState: some View {
        if search.isEmpty {
            ContentUnavailableView("Start typing", systemImage: "magnifyingglass", description: Text("Search for a stop or route by name or number."))
        } else {
            ContentUnavailableView.search(text: search)
        }
    }

    /// Inline message when the idle stops section is empty; discloses why and offers recovery.
    @ViewBuilder
    private var stopsDisclosure: some View {
        if !isLocationAuthorized {
            HStack {
                Text("Turn on location to see nearby stops")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } else if case .proximity(let meters) = searchFilter {
            HStack {
                Text("No stops within \(meters.formattedDistance)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show all") { searchFilter = .none }
            }
        } else {
            Text("No stops available")
                .foregroundStyle(.secondary)
        }
    }

    /// A single-select distance option; the leading icon becomes a checkmark when active.
    private func distanceOption(_ title: String, systemImage: String, filter: SortState) -> some View {
        Button {
            searchFilter = filter
        } label: {
            Label(title, systemImage: searchFilter == filter ? "checkmark" : systemImage)
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
}
