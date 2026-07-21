//
//  TestStopView.swift
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
                                    HStack {
                                        Text(arrival.lineRef)
                                            .monospaced()
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
}
