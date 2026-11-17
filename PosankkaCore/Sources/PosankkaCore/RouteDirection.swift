import FoliBusAPI

/// One direction of a route: its headsign, ordered stops and drawn path.
public struct RouteDirection: Identifiable, Sendable {
    /// GTFS `direction_id` (0 or 1).
    public let id: Int
    public let headsign: String
    public let stops: [Foli.Stop]
    /// Empty when the shape is unavailable.
    public let path: [Foli.Coordinate]

    public var start: Foli.Coordinate? { stops.first?.location }
    /// Nil for a single-stop direction, which has no separate end.
    public var end: Foli.Coordinate? {
        stops.count >= 2 ? stops.last?.location : nil
    }

    /// Path points to frame, falling back to the stops when there's no shape.
    public var framingCoordinates: [Foli.Coordinate] {
        path.isEmpty ? stops.compactMap(\.location) : path
    }

    /// Loads each direction of a route, sorted by `id`. One representative
    /// trip per direction supplies both stops and path.
    public static func load(routeId: String, client: FoliClient) async throws -> [RouteDirection] {
        let trips = try await client.fetchTrips(forRoute: routeId)
        let byDirection = Dictionary(grouping: trips, by: \.directionId)
        return try await withThrowingTaskGroup(of: RouteDirection.self) { group in
            for (directionId, directionTrips) in byDirection {
                let trip = directionTrips[0]  // grouping never yields empty arrays
                group.addTask {
                    async let stops = stops(tripId: trip.tripId, client: client)
                    async let path = path(shapeId: trip.shapeId, client: client)
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

    private static func stops(tripId: String, client: FoliClient) async throws -> [Foli.Stop] {
        let stopTimes = try await client.fetchStopTimes(forTrip: tripId)
            .sorted { $0.stopSequence < $1.stopSequence }
        var stops: [Foli.Stop] = []
        for stopId in stopTimes.compactMap(\.stopId) {
            if let stop = try? await client.stop(for: stopId) {
                stops.append(stop)
            }
        }
        return stops
    }

    private static func path(shapeId: String, client: FoliClient) async -> [Foli.Coordinate] {
        guard let points = try? await client.fetchShapePoints(forShape: shapeId) else { return [] }
        return points.map { Foli.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
