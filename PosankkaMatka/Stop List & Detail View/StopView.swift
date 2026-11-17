//
//  StopView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import UIKit
import FoliBusUI
import PosankkaCore
struct StopView: View {
    let stop: Foli.Stop
    @Environment(AppModel.self) private var model
    @State private var arrivalsStore = ResourceStore<[Foli.Arrival]>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Focus target once the arrivals header exists (the card opens on a spinner).
    @AccessibilityFocusState private var focusArrivals: Bool

    var body: some View {
        Group {
            switch (arrivalsStore.state) {
            case .loading:
                ProgressView()
            case .success(let arrivals):
                VStack {
                    if let error = arrivalsStore.lastError {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                            .background(.yellow.opacity(0.15))
                    }
                    if arrivals.count == 0 {
                        ContentUnavailableView("No Arrivals", systemImage: "pc")
                    } else {
                        List {
                            Section {
                                ForEach(arrivals) { arrival in
                                    arrivalRow(arrival, trip: model.vehicles.latestVehicles.trip(for: arrival))
                                }
                            } header: {
                                // Stacked at accessibility sizes.
                                if dynamicTypeSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: 2) {
                                        arrivalsTitle
                                        refreshStatus
                                    }
                                } else {
                                    HStack {
                                        arrivalsTitle
                                        Spacer()
                                        refreshStatus
                                    }
                                }
                            } footer: {
                                Text("Live stop and bus data refreshes periodically and may not always be accurate.")
                            }
                        }
                        // Animates poll diffs; the load-state animation is below.
                        .animation(reduceMotion ? nil : .spring(.bouncy), value: arrivals)
                    }

                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))}
        }
        // .smooth, not .bouncy: overshoot reads as a scroll and flashes the nav bar hairline.
        .animation(reduceMotion ? nil : .smooth, value: arrivalsStore.state)
        .refreshable {
            await arrivalsStore.refresh(fetch)
        }
        .task {
            // The feed caches server-side for 15-30 s, so ~20 s keeps it current.
            await arrivalsStore.load(fetch)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await arrivalsStore.refresh(fetch)
            }
        }
        .navigationTitle(Text(stop.name))
        .navigationBarTitleDisplayMode(.inline)
        // First arrival only; polls must not pull focus back.
        .onChange(of: arrivalsStore.state) { old, _ in
            if case .loading = old { focusArrivals = true }
        }
        // The banner is visual only. Skipped without a list: the failure view announces itself.
        .onChange(of: arrivalsStore.lastError?.localizedDescription) { old, new in
            if old == nil, let new, arrivalsStore.state.value != nil {
                UIAccessibility.post(notification: .announcement,
                                     argument: String(localized: "Refresh failed: \(new)"))
            }
        }

    }

    private var fetch: @Sendable () async throws -> [Foli.Arrival] {
        let client = model.client
        let stopId = stop.id
        return { try await client.fetchArrivals(for: stopId) }
    }

    /// A row whose bus is live (`trip` non-nil) opens its vehicle card; others
    /// stay plain. `trip` refreshes with each vehicle poll, between arrival fetches.
    @ViewBuilder
    private func arrivalRow(_ arrival: Foli.Arrival, trip: TripKey?) -> some View {
        if let trip {
            Button {
                model.selectVehicle(trip)
            } label: {
                arrivalContent(arrival, showsChevron: true)
            }
            .tint(.primary)
            .accessibilityHint("Tracks this bus live")
            .accessibilityAction(named: "Track Bus") { model.selectVehicle(trip) }
            .contextMenu {
                Button("Track Bus", systemImage: "bus") { model.selectVehicle(trip) }
                // "Notify Me" goes here once stop alerts reach arrival rows.
            }
        } else {
            arrivalContent(arrival, showsChevron: false)
        }
    }

    private func arrivalContent(_ arrival: Foli.Arrival, showsChevron: Bool) -> some View {
        // Stacked at accessibility sizes.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        lineBadge(for: arrival)
                        Text(arrival.destinationDisplay)
                        countdown(for: arrival)
                    }
                    if showsChevron {
                        Spacer()
                        chevron
                    }
                }
            } else {
                HStack(spacing: 12) {
                    lineBadge(for: arrival)
                    Text(arrival.destinationDisplay)
                    Spacer()
                    countdown(for: arrival)
                    if showsChevron { chevron }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            spokenArrival(
                line: arrival.lineRef,
                destination: arrival.destinationDisplay,
                departure: arrival.expectedDepartureDate
            ))
    }

    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// Matches `lineRef` to `route.shortName`; nil falls back to plain text.
    private func route(for arrival: Foli.Arrival) -> Foli.Route? {
        guard let routes = model.routes.state.value else { return nil }
        return routes.first { $0.shortName == arrival.lineRef }
    }

    @ViewBuilder
    private func lineBadge(for arrival: Foli.Arrival) -> some View {
        if let route = route(for: arrival) {
            RouteBadge(route: route)
        } else {
            Text(arrival.lineRef).monospaced()
        }
    }

    /// Re-renders so the countdown ticks between polls.
    private func countdown(for arrival: Foli.Arrival) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            Text(arrival.expectedDepartureDate.formattedInterval(to: .now))
                .font(.footnote)
                .monospacedDigit()
        }
    }

    /// Focus lands here; name the stop, not just "Arrivals".
    private var arrivalsTitle: some View {
        Text("Arrivals")
            .accessibilityLabel("Arrivals for \(stop.name)")
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focusArrivals)
    }

    /// Wall-clock time, since relative wording would read "now" most of the cycle.
    @ViewBuilder
    private var refreshStatus: some View {
        if arrivalsStore.isRefreshing {
            statusText("Updating…")
        } else if let updated = arrivalsStore.lastUpdated {
            statusText("Updated \(updated.formatted(date: .omitted, time: .shortened))")
        }
    }

    /// LocalizedStringKey so `Text` localizes instead of showing the key.
    private func statusText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

/// Screen reader label for an arrival row. Clock time past an hour, "departing now" under a minute.
func spokenArrival(line: String, destination: String, departure: Date) -> String {
    let head = String(localized: "Line \(line) to \(destination)")
    let interval = departure.timeIntervalSince(.now)
    let minutes = Int((interval / 60).rounded())
    if minutes >= 60 {
        return String(localized: "\(head), departing at \(departure.formatted(date: .omitted, time: .shortened))")
    }
    if interval > 0, minutes == 0 {
        return String(localized: "\(head), departing now")
    }
    return "\(head), \(departure.formatted(.relative(presentation: .named)))"
}
