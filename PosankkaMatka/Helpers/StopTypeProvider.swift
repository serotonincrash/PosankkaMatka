//
//  StopTypeProvider.swift
//  PosankkaMatka
//
//  Created by sero on 8/13/26.
//

import Observation
import FoliBusUI

/// Determines each stop's vehicle mode so the map can show the right marker
/// (bus vs. boat).
///
/// GTFS doesn't put a vehicle type on stops — it lives on routes (`route_type`,
/// where `3` = bus and `4` = ferry/boat). A stop is a boat stop when it's served
/// by at least one ferry route, so this walks ferry routes → their trips → their
/// stop times to collect the affected stop IDs. With Föli's two ferry routes that
/// is a handful of requests, run once off the `body` path (and then served from
/// the client's cache on any later call).
@MainActor
@Observable
final class StopTypeProvider {
    /// Stop IDs served by a ferry/boat route. Read by the map; computed in `load`.
    private(set) var boatStopIDs: Set<Foli.Stop.ID> = []

    /// GTFS `route_type` for ferry / water-bus services.
    private static let ferryRouteType = 4

    /// Collects the IDs of every stop served by a ferry route.
    ///
    /// Failures are per-request and non-fatal: a trip whose stop times can't be
    /// fetched is simply skipped, leaving the default (bus) marker for its stops.
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
