//
//  RouteDetailStore.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import CoreLocation
import Observation
import FoliBusUI

/// Selected-route detail shared by the map and the card: per-direction stops +
/// polyline (both come from one representative trip) and the shown direction;
/// `selectedDirectionId` drives map + list together.
@MainActor
@Observable
final class RouteDetailStore {
    /// Per-direction data; a fresh store per route clears stale data to `.loading`.
    private(set) var directions = ResourceStore<[RouteDirection]>()
    /// The direction currently shown across map + list.
    var selectedDirectionId: Int?

    var allDirections: [RouteDirection] { directions.state.value ?? [] }
    var selectedDirection: RouteDirection? {
        allDirections.first { $0.id == selectedDirectionId }
    }

    /// Loads directions and selects the first; resets first so a new route doesn't flash the old one.
    func load(routeId: String, using foli: FoliService) async {
        selectedDirectionId = nil
        directions = ResourceStore<[RouteDirection]>()
        await directions.load(Self.fetch(routeId: routeId, using: foli))
        selectedDirectionId = allDirections.first?.id
    }

    func reset() {
        selectedDirectionId = nil
    }

    /// route → per-direction stops + path; one representative trip per direction yields both, fetched concurrently.
    private static func fetch(routeId: String, using foli: FoliService) -> @Sendable () async throws -> [RouteDirection] {
        return {
            let trips = try await foli.fetchTrips(forRoute: routeId)
            let byDirection = Dictionary(grouping: trips, by: \.directionId)
            return try await withThrowingTaskGroup(of: RouteDirection.self) { group in
                for (directionId, directionTrips) in byDirection {
                    // Dictionary(grouping:) never yields empty arrays.
                    let trip = directionTrips[0]
                    group.addTask {
                        async let stops = resolveStops(tripId: trip.tripId, using: foli)
                        async let path = resolvePath(shapeId: trip.shapeId, using: foli)
                        return RouteDirection(
                            id: directionId,
                            headsign: trip.tripHeadsign,
                            stops: try await stops,
                            path: await path
                        )
                    }
                }
                var result: [RouteDirection] = []
                for try await direction in group { result.append(direction) }
                // Task completion order is nondeterministic; sort by directionId.
                return result.sorted { $0.id < $1.id }
            }
        }
    }

    private static func resolveStops(tripId: String, using foli: FoliService) async throws -> [Foli.Stop] {
        let stopTimes = try await foli.fetchStopTimes(forTrip: tripId)
            .sorted { $0.stopSequence < $1.stopSequence }
        var stops: [Foli.Stop] = []
        for stopTime in stopTimes {
            guard let stopId = stopTime.stopId else { continue }
            if let stop = try? await foli.fetchStop(id: stopId) {
                stops.append(stop)
            }
        }
        return stops
    }

    private static func resolvePath(shapeId: String, using foli: FoliService) async -> [CLLocationCoordinate2D] {
        guard let points = try? await foli.fetchShapePoints(forShape: shapeId) else { return [] }
        return points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
