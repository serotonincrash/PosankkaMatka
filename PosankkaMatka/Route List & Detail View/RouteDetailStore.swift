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
    private let client: FoliClient
    /// Per-direction data; a fresh store per route clears stale data to `.loading`.
    private(set) var directions = ResourceStore<[RouteDirection]>()
    /// The direction currently shown across map + list.
    var selectedDirectionId: Int?

    init(client: FoliClient) {
        self.client = client
    }

    var allDirections: [RouteDirection] { directions.state.value ?? [] }
    var selectedDirection: RouteDirection? {
        allDirections.first { $0.id == selectedDirectionId }
    }

    /// Loads directions and selects the first; resets first so a new route doesn't flash the old one.
    func load(routeId: String) async {
        selectedDirectionId = nil
        let store = ResourceStore<[RouteDirection]>()
        directions = store
        await store.load(Self.fetch(routeId: routeId, client: client))
        // Superseded by another load or a reset while in flight: selecting a
        // direction now would draw a stale route with no card up.
        guard !Task.isCancelled, directions === store else { return }
        selectedDirectionId = allDirections.first?.id
    }

    /// Clears the selection and swaps in a fresh store, so an in-flight load
    /// sees it was superseded and doesn't re-select a direction.
    func reset() {
        selectedDirectionId = nil
        directions = ResourceStore<[RouteDirection]>()
    }

    /// route → per-direction stops + path; one representative trip per direction yields both, fetched concurrently.
    private static func fetch(routeId: String, client: FoliClient) -> @Sendable () async throws -> [RouteDirection] {
        return {
            let trips = try await client.fetchTrips(forRoute: routeId)
            let byDirection = Dictionary(grouping: trips, by: \.directionId)
            return try await withThrowingTaskGroup(of: RouteDirection.self) { group in
                for (directionId, directionTrips) in byDirection {
                    // Dictionary(grouping:) never yields empty arrays.
                    let trip = directionTrips[0]
                    group.addTask {
                        async let stops = resolveStops(tripId: trip.tripId, client: client)
                        async let path = resolvePath(shapeId: trip.shapeId, client: client)
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

    private static func resolveStops(tripId: String, client: FoliClient) async throws -> [Foli.Stop] {
        let stopTimes = try await client.fetchStopTimes(forTrip: tripId)
            .sorted { $0.stopSequence < $1.stopSequence }
        var stops: [Foli.Stop] = []
        for stopTime in stopTimes {
            guard let stopId = stopTime.stopId else { continue }
            if let stop = try? await client.stop(for: stopId) {
                stops.append(stop)
            }
        }
        return stops
    }

    private static func resolvePath(shapeId: String, client: FoliClient) async -> [CLLocationCoordinate2D] {
        guard let points = try? await client.fetchShapePoints(forShape: shapeId) else { return [] }
        return points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
