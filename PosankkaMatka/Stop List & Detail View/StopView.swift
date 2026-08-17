//
//  StopView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import FoliBusUI
struct StopView: View {
    @Namespace var namespace
    var stopWithDistance: StopWithDistance
    @FoliService var foli
    @Environment(ResourceStore<[Foli.Route]>.self) private var routesStore
    @State private var arrivals = ResourceStore<[Foli.Arrival]>()

    var body: some View {
        Group {
            switch (arrivals.state) {
            case .loading:
                ProgressView()
            case .success(let arrivals):
                VStack {
                    if arrivals.count == 0 {
                        ContentUnavailableView("No Arrivals", systemImage: "pc")
                    } else {
                        List {
                            Section("Arrivals") {
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
                                        Text(arrival.expectedDepartureDate.formattedInterval(to: .now))
                                            .font(.footnote)
                                    }
                                }
                                
                            }
                        }
                    }
                    
                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))}
        }
        .animation(.spring(.bouncy), value: arrivals.state)
        .refreshable {
            await arrivals.refresh(fetch)
        }
        .task {
            await arrivals.load(fetch)
        }
        .navigationTitle(Text(stopWithDistance.stop.name))

    }

    private var fetch: @Sendable () async throws -> [Foli.Arrival] {
        let foli = foli
        let stopId = stopWithDistance.stop.id
        return { try await foli.fetchArrivals(for: stopId) }
    }

    /// The route serving an arrival (`lineRef` == `route.shortName`); `nil` until
    /// routes load or when unmatched, falling back to plain line text.
    private func route(for arrival: Foli.Arrival) -> Foli.Route? {
        guard let routes = routesStore.state.value else { return nil }
        return routes.first { $0.shortName == arrival.lineRef }
    }
}
