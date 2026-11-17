import Foundation
import FoliBusAPI

extension Foli.Coordinate {
    /// Great-circle (haversine) distance in meters.
    public func distance(to other: Foli.Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

extension Collection where Element == Foli.Stop {
    /// Stops nearest-first with their distances, optionally capped at
    /// `maxDistance` meters. Stops without a valid coordinate are skipped.
    public func nearest(
        to origin: Foli.Coordinate,
        withinMeters maxDistance: Double? = nil
    ) -> [(stop: Foli.Stop, distance: Double)] {
        compactMap { stop -> (stop: Foli.Stop, distance: Double)? in
            guard let location = stop.location, location.isValid else { return nil }
            let distance = location.distance(to: origin)
            if let maxDistance, distance >= maxDistance { return nil }
            return (stop, distance)
        }
        .sorted { $0.distance < $1.distance }
    }

    /// Stops whose name or code contains `query`, ignoring case.
    public func matching(_ query: String) -> [Foli.Stop] {
        filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.code ?? "").localizedCaseInsensitiveContains(query)
        }
    }
}

extension Collection where Element == Foli.Route {
    /// Sorted by the leading number of `shortName`, then the full name;
    /// non-numeric names last.
    public func sortedByLine() -> [Foli.Route] {
        sorted { lhs, rhs in
            switch (Self.leadingNumber(lhs.shortName), Self.leadingNumber(rhs.shortName)) {
            case let (l?, r?) where l != r: l < r
            case (.some, .none): true
            case (.none, .some): false
            default: lhs.shortName.localizedStandardCompare(rhs.shortName) == .orderedAscending
            }
        }
    }

    /// Routes whose line number or name contains `query`, ignoring case.
    public func matching(_ query: String) -> [Foli.Route] {
        filter {
            $0.shortName.localizedCaseInsensitiveContains(query)
                || $0.longName.localizedCaseInsensitiveContains(query)
        }
    }

    private static func leadingNumber(_ s: String) -> Int? {
        Int(s.prefix { $0.isNumber })
    }
}

extension FoliClient {
    /// IDs of stops served by a ferry route (GTFS `route_type` 4). Failed
    /// fetches are skipped, leaving those stops drawn as bus stops.
    public nonisolated func ferryStopIDs(in routes: [Foli.Route]) async -> Set<Foli.Stop.ID> {
        var ids: Set<Foli.Stop.ID> = []
        for route in routes where route.type == 4 {
            guard let trips = try? await fetchTrips(forRoute: route.id) else { continue }
            for trip in trips {
                guard let stopTimes = try? await fetchStopTimes(forTrip: trip.tripId) else { continue }
                ids.formUnion(stopTimes.compactMap(\.stopId))
            }
        }
        return ids
    }
}
