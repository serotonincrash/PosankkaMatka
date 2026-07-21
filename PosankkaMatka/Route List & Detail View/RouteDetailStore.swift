//
//  RouteDetailStore.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import CoreLocation
import Observation
import FoliBusUI

/// Shared state for a selected route's detail: the per-direction data (each
/// direction's ordered stops AND its polyline path, joined via the trip that
/// carries both `directionId` and `shapeId`) plus the currently shown direction.
/// Owned by `HomeView`, read by the map and the pushed list so one
/// `selectedDirectionId` drives the drawn line, the start/end pins, the camera,
/// and the stop list together.
@MainActor
@Observable
final class RouteDetailStore {
    /// Loading/success/failure for the joined per-direction data. Replaced with a
    /// fresh store per route so a route switch clears the previous route's data
    /// (back to `.loading`) immediately rather than lingering.
    private(set) var directions = ResourceStore<[RouteDirection]>()
    /// The direction currently shown across map + list.
    var selectedDirectionId: Int?

    var allDirections: [RouteDirection] { directions.state.value ?? [] }
    var selectedDirection: RouteDirection? {
        allDirections.first { $0.id == selectedDirectionId }
    }

    /// Fetches the route's directions — joining stops and shape path per direction
    /// — and defaults the selection to the first direction. Resets first so a new
    /// route doesn't briefly show the previous one's data.
    func load(routeId: String, using foli: FoliService) async {
        selectedDirectionId = nil
        directions = ResourceStore<[RouteDirection]>()  // fresh → clears prior route, back to .loading
        await directions.load(Self.fetch(routeId: routeId, using: foli))
        selectedDirectionId = allDirections.first?.id
    }

    func reset() {
        selectedDirectionId = nil
    }

    /// route → per-direction (stops + path). For each direction a representative
    /// trip yields both its ordered stops (via stop times) and its polyline (via
    /// the trip's shape), fetched concurrently.
    private static func fetch(routeId: String, using foli: FoliService) -> @Sendable () async throws -> [RouteDirection] {
        return {
            let trips = try await foli.fetchTrips(forRoute: routeId)
            let byDirection = Dictionary(grouping: trips, by: \.directionId)
            return try await withThrowingTaskGroup(of: RouteDirection.self) { group in
                for directionId in byDirection.keys.sorted() {
                    guard let trip = byDirection[directionId]?.first else { continue }
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
