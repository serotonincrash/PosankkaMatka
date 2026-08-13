//
//  SearchList.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import SwiftUI
import UIKit
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
    /// derived here so `body` stays pure rendering. Empty when there's no location
    /// or when the proximity filter excludes everything — `stopsDisclosure` covers
    /// both cases so the section never vanishes silently.
    let nearbyStops: [StopWithDistance]
    /// Whether location is authorized — resolved once by the parent instead of
    /// calling into `LocationManager` from `body`.
    let isLocationAuthorized: Bool
    /// Distance filter, bound to the persisted `@Forever` value in the parent.
    @Binding var searchFilter: SortState
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?

    /// Idle "Nearby Stops" rows shown before the "Show all stops" disclosure.
    private static let nearbyLimit = 25
    /// Whether the user expanded the idle nearby list past `nearbyLimit`.
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
        // A filter change re-scopes the list, so collapse back to the capped view
        // rather than leaving a possibly-huge expansion open.
        .onChange(of: searchFilter) { _, _ in
            showsAllNearbyStops = false
        }
        .toolbar {
            // The proximity filter only affects the nearby (idle) list and needs
            // a location to mean anything, so the control is shown only then.
            if showsFilterMenu {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // A flat, single-select group under one header. Buttons are
                        // used instead of a `Picker` so the options sit inline — a
                        // `Picker` in a `Menu` nests behind its label as a submenu,
                        // hiding the actual choices.
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

    /// Rows actually rendered: the idle nearby list is capped at `nearbyLimit`
    /// until the user expands it, while a search shows every match uncapped.
    private var visibleStopRows: [StopWithDistance] {
        guard !isSearching else { return stopRows }
        return showsAllNearbyStops ? stopRows : Array(stopRows.prefix(Self.nearbyLimit))
    }

    /// The idle list shows the "Show all stops" affordance only when it actually
    /// has more stops than the cap and hasn't been expanded yet.
    private var showsNearbyDisclosure: Bool {
        !isSearching && !showsAllNearbyStops && stopRows.count > Self.nearbyLimit
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

    /// The full-sheet empty state fires only for a text search with no matches
    /// anywhere; idle always renders the list — an empty nearby set is disclosed
    /// in place by `stopsDisclosure` rather than blanking the whole sheet.
    private var isListEmpty: Bool { isSearching && stopRows.isEmpty && routeRows.isEmpty }

    /// In search, show the stops section only if it has matches; in idle it
    /// always shows (rows, or a disclosure explaining the empty state).
    private var showsStopsSection: Bool { isSearching ? !stopRows.isEmpty : true }

    private var stopSectionTitle: String { isSearching ? "Stops" : "Nearby Stops" }

    /// The proximity filter is meaningful only in the idle list with a location.
    private var showsFilterMenu: Bool { isLocationAuthorized && !isSearching }

    // MARK: - Empty / disclosure states

    /// Full-sheet empty state, reached only while searching (see `isListEmpty`).
    @ViewBuilder
    private var emptyState: some View {
        if search.isEmpty {
            ContentUnavailableView("Start typing", systemImage: "magnifyingglass", description: Text("Search for a stop or route by name or number."))
        } else {
            ContentUnavailableView.search(text: search)
        }
    }

    /// Inline message shown inside the stops section when it has no rows (idle
    /// only — a search with no stop matches simply omits the section). Discloses
    /// *why* it's empty and offers the recovery action.
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
                Text("No stops within \(formattedDistance(meters))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show all") { searchFilter = .none }
            }
        } else {
            Text("No stops available")
                .foregroundStyle(.secondary)
        }
    }

    /// "500 m" / "2 km" — matches the labels used in the filter menu.
    private func formattedDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : "\(Int(meters / 1000)) km"
    }

    /// A single-select distance option. The leading icon swaps to a checkmark when
    /// this option is active — the system menu convention — so the row's leading
    /// glyph stays put (no layout shift between selected and unselected states).
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
