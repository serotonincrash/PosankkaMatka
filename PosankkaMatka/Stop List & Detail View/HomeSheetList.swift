//
//  HomeSheetList.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import SwiftUI
import UIKit
import FoliBusUI
import PosankkaCore

/// The home-sheet list: nearby stops and routes.
struct HomeSheetList: View {
    @Environment(\.isSearching) var isSearching

    let search: String
    let stops: [Foli.Stop]
    let routes: [Foli.Route]
    let nearbyStops: [StopWithDistance]
    let isLocationAuthorized: Bool
    @Binding var searchFilter: DistanceFilter
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?

    private static let nearbyLimit = 25
    @State private var showsAllNearbyStops = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Moves VoiceOver focus off the grabber when the sheet re-presents.
    @AccessibilityFocusState private var focusStopsHeader: Bool

    var body: some View {
        Group {
            if isListEmpty {
                emptyState
            } else {
                List {
                    if showsStopsSection {
                        Section {
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
                                    .accessibilityLabel(stopWithDistance.spokenDescription)
                                    .accessibilityHint("Opens live arrivals for this stop")
                                    .stopInputLabels(stopID: stopWithDistance.stop.id, name: stopWithDistance.stop.name)
                                }
                                if showsNearbyDisclosure {
                                    Button("Show all \(stopRows.count) stops") {
                                        showsAllNearbyStops = true
                                    }
                                }
                            }
                        } header: {
                            // Header trait for the Headings rotor.
                            Text(stopSectionTitle)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($focusStopsHeader)
                        }
                    }
                    if !routeRows.isEmpty {
                        Section {
                            ForEach(routeRows) { route in
                                Button {
                                    selectedRoute = route
                                } label: {
                                    RouteRow(route: route)
                                }
                                .tint(.primary)
                                .accessibilityLabel(route.spokenDescription)
                                .accessibilityHint("Opens the route's stops and live vehicles")
                                .accessibilityInputLabels([
                                    String(localized: "Route \(route.shortName)"),
                                    route.longName
                                ])
                            }
                        } header: {
                            Text("Routes")
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .onAppear { focusStopsHeader = true }
            }
        }
        .navigationTitle(Text("Föli"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: searchFilter) { _, _ in
            showsAllNearbyStops = false
        }
        .toolbar {
            if showsFilterMenu {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // `.inline` keeps the Picker flat; otherwise it nests as a submenu.
                        Section("Show stops within") {
                            Picker("Distance", selection: $searchFilter) {
                                Label("Any distance", systemImage: "infinity")
                                    .tag(DistanceFilter.none)
                                Label("500 m", systemImage: "location")
                                    .tag(DistanceFilter.proximity(500))
                                Label("1 km", systemImage: "location")
                                    .tag(DistanceFilter.proximity(1000))
                                Label("2 km", systemImage: "location")
                                    .tag(DistanceFilter.proximity(2000))
                            }
                            .pickerStyle(.inline)
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter stops by distance")
                    .accessibilityHint("Sets the maximum distance for nearby stops")
                }
            }
        }
    }

    // MARK: - Derived rows

    /// Nearby rows when idle, name/code matches when searching.
    private var stopRows: [StopWithDistance] {
        guard isSearching else { return nearbyStops }
        guard !search.isEmpty else { return [] }
        return stops.matching(search).map { StopWithDistance($0) }
    }

    /// Nearby is capped until expanded; search is uncapped.
    private var visibleStopRows: [StopWithDistance] {
        guard !isSearching else { return stopRows }
        return showsAllNearbyStops ? stopRows : Array(stopRows.prefix(Self.nearbyLimit))
    }

    private var showsNearbyDisclosure: Bool {
        !isSearching && !showsAllNearbyStops && stopRows.count > Self.nearbyLimit
    }

    private var routeRows: [Foli.Route] {
        let sorted = routes.sortedByLine()
        guard isSearching else { return sorted }
        guard !search.isEmpty else { return [] }
        return sorted.matching(search)
    }

    /// Only a search with no matches is empty; idle always shows the list.
    private var isListEmpty: Bool { isSearching && stopRows.isEmpty && routeRows.isEmpty }

    private var showsStopsSection: Bool { isSearching ? !stopRows.isEmpty : true }

    /// LocalizedStringKey so `Text` localizes instead of showing the key.
    private var stopSectionTitle: LocalizedStringKey { isSearching ? "Stops" : "Nearby Stops" }

    private var showsFilterMenu: Bool { isLocationAuthorized && !isSearching }

    // MARK: - Empty / disclosure states

    @ViewBuilder
    private var emptyState: some View {
        if search.isEmpty {
            ContentUnavailableView("Start typing", systemImage: "magnifyingglass", description: Text("Search for a stop or route by name or number."))
        } else {
            ContentUnavailableView.search(text: search)
        }
    }

    @ViewBuilder
    private var stopsDisclosure: some View {
        if !isLocationAuthorized {
            adaptiveRow {
                Text("Turn on location to see nearby stops")
                    .foregroundStyle(.secondary)
            } action: {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .accessibilityHint("Opens system settings for the purpose of granting location permissions")
            }
        } else if case .proximity(let meters) = searchFilter {
            adaptiveRow {
                Text("No stops within \(meters.formattedDistance)")
                    .foregroundStyle(.secondary)
            } action: {
                Button("Show all") { searchFilter = .none }
                    .accessibilityHint("Clears the distance filter")
            }
        } else {
            Text("No stops available")
                .foregroundStyle(.secondary)
        }
    }

    /// Stacks at accessibility sizes.
    @ViewBuilder
    private func adaptiveRow<Message: View, Action: View>(
        @ViewBuilder _ message: () -> Message,
        @ViewBuilder action: () -> Action
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                message()
                action()
            }
        } else {
            HStack {
                message()
                Spacer()
                action()
            }
        }
    }

    // MARK: - Rows

    private struct StopRow: View {
        let stopWithDistance: StopWithDistance
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // Stacked at accessibility sizes; side by side, names break mid-word.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        icon
                        StopCode(id: stopWithDistance.stop.id)
                    }
                    Text(stopWithDistance.stop.name)
                    distance
                }
            } else {
                HStack {
                    icon
                    StopCode(id: stopWithDistance.stop.id)
                    Text(stopWithDistance.stop.name)
                    Spacer()
                    distance
                }
            }
        }

        private var icon: some View {
            Image(systemName: "signpost.right.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .accessibilityHidden(true)
        }

        @ViewBuilder
        private var distance: some View {
            if let distanceText = stopWithDistance.distanceText {
                Text(distanceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct RouteRow: View {
        let route: Foli.Route
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    RouteBadge(route: route)
                    Text(route.longName)
                }
            } else {
                HStack(spacing: 12) {
                    RouteBadge(route: route)
                    Text(route.longName)
                    Spacer()
                }
            }
        }
    }
}
