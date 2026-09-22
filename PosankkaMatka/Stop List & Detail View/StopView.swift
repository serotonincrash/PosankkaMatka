//
//  StopView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import FoliBusUI
struct StopView: View {
    var stopWithDistance: StopWithDistance
    @FoliService var foli
    @Environment(ResourceStore<[Foli.Route]>.self) private var routesStore
    @State private var arrivalsStore = ResourceStore<[Foli.Arrival]>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                                    HStack(spacing: 12) {
                                        if let route = route(for: arrival) {
                                            RouteBadge(route: route)
                                        } else {
                                            Text(arrival.lineRef)
                                                .monospaced()
                                        }
                                        Text(arrival.destinationDisplay)
                                        Spacer()
                                        // Ticks between polls so "N min" counts
                                        // down instead of freezing.
                                        TimelineView(.periodic(from: .now, by: 15)) { _ in
                                            Text(arrival.expectedDepartureDate.formattedInterval(to: .now))
                                                .font(.footnote)
                                                .monospacedDigit()
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(spokenArrival(arrival))
                                }
                            } header: {
                                HStack {
                                    Text("Arrivals")
                                        .accessibilityAddTraits(.isHeader)
                                        .accessibilityFocused($focusArrivals)
                                    Spacer()
                                    // "Updating…" mid-fetch, else wall-clock time —
                                    // relative wording would read "now" most of
                                    // the 20 s cycle.
                                    if arrivalsStore.isRefreshing {
                                        Text("Updating…")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .textCase(nil)
                                    } else if let updated = arrivalsStore.lastUpdated {
                                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .textCase(nil)
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

    /// Row label for screen readers, with spoken time phrasing ("Line 32 to
    /// Kauppatori, departing in 5 minutes"). Buckets mirror
    /// `formattedInterval` but in words — "5 min" reads poorly aloud.
    private func spokenArrival(_ arrival: Foli.Arrival) -> String {
        let line = route(for: arrival)?.shortName ?? arrival.lineRef
        let interval = arrival.expectedDepartureDate.timeIntervalSince(.now)
        let minutes = Int((interval / 60).rounded())
        let head = "Line \(line) to \(arrival.destinationDisplay)"
        if interval <= 0 {
            let ago = abs(minutes)
            return "\(head), departed \(ago) minute\(ago == 1 ? "" : "s") ago"
        }
        if minutes >= 60 {
            let clock = arrival.expectedDepartureDate.formatted(date: .omitted, time: .shortened)
            return "\(head), departing at \(clock)"
        }
        return minutes == 0
            ? "\(head), departing now"
            : "\(head), departing in \(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}
