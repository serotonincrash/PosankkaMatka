//
//  StopTypeProvider.swift
//  PosankkaMatka
//
//  Created by sero on 8/13/26.
//

import Observation
import FoliBusUI

/// Maps stops to their vehicle mode (bus vs. boat). GTFS puts the type on routes
/// (`route_type`: 3 = bus, 4 = ferry), so a stop is a boat stop when served by a
/// ferry route — this walks ferry routes → trips → stop times to find those IDs.
@MainActor
@Observable
final class StopTypeProvider {
    /// Stop IDs served by a ferry/boat route. Read by the map; computed in `load`.
    private(set) var boatStopIDs: Set<Foli.Stop.ID> = []

    /// GTFS `route_type` for ferry / water-bus services.
    private static let ferryRouteType = 4

    /// Collects stops served by ferry routes; failures skip a trip (bus fallback).
    func load(routes: [Foli.Route], using foli: FoliService) async {
        let ferryRouteIDs = routes.filter { $0.type == Self.ferryRouteType }.map(\.id)
        guard !ferryRouteIDs.isEmpty else { return }

        var boatStops: Set<Foli.Stop.ID> = []
        for routeID in ferryRouteIDs {
            guard let trips = try? await foli.fetchTrips(forRoute: routeID) else { continue }
            for trip in trips {
                guard let stopTimes = try? await foli.fetchStopTimes(forTrip: trip.tripId) else { continue }
                boatStops.formUnion(stopTimes.compactMap(\.stopId))
            }
        }
        boatStopIDs = boatStops
    }
}
