//
//  RouteDetailList.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import FoliBusUI

/// The pushed detail for a selected route: its stops grouped into a section per
/// direction (titled by headsign). The route's line is drawn on the shared home
/// map by `HomeView`, so this detail is list-only. Tapping a stop opens it.
struct RouteDetailList: View {
    let route: Foli.Route
    @Binding var selectedStopID: Foli.Stop.ID?
    @FoliService var foli

    @State private var directionsStore = ResourceStore<[RouteDirection]>()

    var body: some View {
        Group {
            switch directionsStore.state {
            case .loading:
                ProgressView()
            case .success(let directions):
                List {
                    ForEach(directions) { direction in
                        Section(direction.headsign) {
                            ForEach(direction.stops) { stop in
                                Button {
                                    selectedStopID = stop.id
                                } label: {
                                    HStack {
                                        Text(stop.id).monospaced()
                                        Text(stop.name)
                                        Spacer()
                                    }
                                }
                                .tint(.primary)
                            }
                        }
                    }
                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            }
        }
        .navigationTitle(route.fullDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await directionsStore.load(directionsFetch)
        }
    }

    private var directionsFetch: @Sendable () async throws -> [RouteDirection] {
        let foli = foli
        let routeId = route.id
        return {
            let trips = try await foli.fetchTrips(forRoute: routeId)
            // One representative trip per direction names its section.
            let byDirection = Dictionary(grouping: trips, by: \.directionId)
            var directions: [RouteDirection] = []
            for directionId in byDirection.keys.sorted() {
                guard let trip = byDirection[directionId]?.first else { continue }
                let stopTimes = try await foli.fetchStopTimes(forTrip: trip.tripId)
                    .sorted { $0.stopSequence < $1.stopSequence }
                var stops: [Foli.Stop] = []
                for stopTime in stopTimes {
                    guard let stopId = stopTime.stopId else { continue }
                    if let stop = try? await foli.fetchStop(id: stopId) {
                        stops.append(stop)
                    }
                }
                directions.append(RouteDirection(id: directionId, headsign: trip.tripHeadsign, stops: stops))
            }
            return directions
        }
    }
}
