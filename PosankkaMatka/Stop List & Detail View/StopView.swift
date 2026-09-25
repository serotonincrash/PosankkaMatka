//
//  StopView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import UIKit
import FoliBusUI
struct StopView: View {
    var stopWithDistance: StopWithDistance
    @FoliService var foli
    @Environment(ResourceStore<[Foli.Route]>.self) private var routesStore
    @State private var arrivalsStore = ResourceStore<[Foli.Arrival]>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Steers VoiceOver to the arrivals header once it exists (the card
    /// presents with a spinner, so there's nothing earlier to focus).
    @AccessibilityFocusState private var focusArrivals: Bool

    var body: some View {
        Group {
            switch (arrivalsStore.state) {
            case .loading:
                ProgressView()
            case .success(let arrivals):
                VStack {
                    // A failed refresh keeps the list up and reports here.
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
                                    // Accessibility sizes stack the row —
                                    // side by side, the countdown column
                                    // squeezes the destination text.
                                    Group {
                                        if dynamicTypeSize.isAccessibilitySize {
                                            VStack(alignment: .leading, spacing: 4) {
                                                lineBadge(for: arrival)
                                                Text(arrival.destinationDisplay)
                                                countdown(for: arrival)
                                            }
                                        } else {
                                            HStack(spacing: 12) {
                                                lineBadge(for: arrival)
                                                Text(arrival.destinationDisplay)
                                                Spacer()
                                                countdown(for: arrival)
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
                            } header: {
                                // The status caption stacks under the title
                                // at accessibility sizes instead of folding
                                // into a trailing sliver.
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
                        // Animate poll diffs (rows sliding/reordering), beyond
                        // the load-state animation below.
                        .animation(reduceMotion ? nil : .spring(.bouncy), value: arrivals)
                    }

                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))}
        }
        // .smooth, not .bouncy: an overshooting spring pushes the fresh list
        // past its resting spot for a frame, which the List reads as scrolled
        // — the nav bar hairline flashes in under the title.
        .animation(reduceMotion ? nil : .smooth, value: arrivalsStore.state)
        .refreshable {
            await arrivalsStore.refresh(fetch)
        }
        .task {
            // Load, then poll: the SM feed caches server-side for 15–30 s, so
            // ~20 s keeps the list current without hammering it.
            await arrivalsStore.load(fetch)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await arrivalsStore.refresh(fetch)
            }
        }
        .navigationTitle(Text(stopWithDistance.stop.name))
        .navigationBarTitleDisplayMode(.inline)
        // First arrival only: focus the header when the list materializes;
        // poll refreshes (success → success) must never yank focus back.
        .onChange(of: arrivalsStore.state) { old, _ in
            if case .loading = old { focusArrivals = true }
        }
        // The banner is visual only; tell VoiceOver a refresh failed. Gated on
        // a visible list — the full-screen failure view is self-announcing as
        // new content.
        .onChange(of: arrivalsStore.lastError?.localizedDescription) { old, new in
            if old == nil, let new, arrivalsStore.state.value != nil {
                UIAccessibility.post(notification: .announcement,
                                     argument: "Refresh failed: \(new)")
            }
        }

    }

    private var fetch: @Sendable () async throws -> [Foli.Arrival] {
        let foli = foli
        let stopId = stopWithDistance.stop.id
        return { try await foli.fetchArrivals(for: stopId) }
    }

    /// The route serving an arrival (`lineRef` == `route.shortName`); nil until
    /// routes load or when unmatched (falls back to plain line text).
    private func route(for arrival: Foli.Arrival) -> Foli.Route? {
        guard let routes = routesStore.state.value else { return nil }
        return routes.first { $0.shortName == arrival.lineRef }
    }

    /// Badge or plain line text for an arrival row.
    @ViewBuilder
    private func lineBadge(for arrival: Foli.Arrival) -> some View {
        if let route = route(for: arrival) {
            RouteBadge(route: route)
        } else {
            Text(arrival.lineRef).monospaced()
        }
    }

    /// Ticks between polls so "N min" counts down instead of freezing.
    private func countdown(for arrival: Foli.Arrival) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            Text(arrival.expectedDepartureDate.formattedInterval(to: .now))
                .font(.footnote)
                .monospacedDigit()
        }
    }

    /// Focus lands here when the card's content materializes — say which
    /// stop's arrivals these are, not just "Arrivals".
    private var arrivalsTitle: some View {
        Text("Arrivals")
            .accessibilityLabel("Arrivals for \(stopWithDistance.stop.name)")
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focusArrivals)
    }

    /// "Updating…" mid-fetch, else wall-clock time — relative wording would
    /// read "now" most of the 20 s cycle.
    @ViewBuilder
    private var refreshStatus: some View {
        if arrivalsStore.isRefreshing {
            statusText("Updating…")
        } else if let updated = arrivalsStore.lastUpdated {
            statusText("Updated \(updated.formatted(date: .omitted, time: .shortened))")
        }
    }

    /// LocalizedStringKey (not String) so `Text` looks the keys up instead
    /// of rendering them verbatim.
    private func statusText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

/// Row label for screen readers ("Line 32 to Kauppatori, departing in 5
/// minutes"). The relative form words the minute buckets (and their plurals,
/// in the device locale) natively; an hour or more out reads better as clock
/// time, and under a minute as "departing now".
func spokenArrival(line: String, destination: String, departure: Date) -> String {
    let head = "Line \(line) to \(destination)"
    let interval = departure.timeIntervalSince(.now)
    let minutes = Int((interval / 60).rounded())
    if minutes >= 60 {
        return "\(head), departing at \(departure.formatted(date: .omitted, time: .shortened))"
    }
    if interval > 0, minutes == 0 {
        return "\(head), departing now"
    }
    return "\(head), \(departure.formatted(.relative(presentation: .named)))"
}
