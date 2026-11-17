import Foundation
import FoliBusAPI

/// One bus's trip as a stop rail: stops already passed, the one it's heading
/// for, and those after.
///
/// Live SIRI has no `previousCalls`, so passed stops come only from a matched
/// `RouteDirection` (without times); unmatched, the rail starts at the next stop.
public struct VehicleJourney: Sendable {
    public enum CallState: Equatable, Sendable {
        case passed
        /// The stop the bus is heading for; `progress` is along the segment
        /// into it, 1 when the bus is at the stop.
        case current(progress: Double)
        case upcoming
    }

    public struct Call: Identifiable, Sendable {
        /// Position in `calls`; a stop can appear twice on a loop.
        public let id: Int
        public let stopID: Foli.Stop.ID
        public let name: String
        public let coordinate: Foli.Coordinate?
        public let expectedArrival: Date?
        public let aimedArrival: Date?
        public let state: CallState

        /// Expected time, else the aimed time shifted by the trip's delay.
        public func estimatedArrival(delay: TimeInterval?) -> Date? {
            expectedArrival ?? aimedArrival?.addingTimeInterval(delay ?? 0)
        }
    }

    public let trip: TripKey
    public let calls: [Call]
    /// Index in `calls` of the `.current` call; nil when the feed gave no stops.
    public let nextStopIndex: Int?
    /// Positive is late.
    public let delay: TimeInterval?
    public let destinationName: String?
    /// Matched shape, else straight lines between call coordinates.
    public let path: [Foli.Coordinate]
    /// Path segment to start projecting the bus from, so a loop's later pass
    /// near the same spot isn't picked.
    private let pathSearchStart: Int

    public var terminus: Call? { calls.last }

    /// `direction` is used only if the vehicle's upcoming stops align with it.
    public init(
        vehicle: Foli.VehicleLocation,
        direction: RouteDirection?,
        stops: [Foli.Stop.ID: Foli.Stop] = [:]
    ) {
        trip = TripKey(vehicle)
        delay = vehicle.delayInSeconds
        destinationName = vehicle.destinationName

        let ahead = Self.aheadCalls(of: vehicle)
        let alignment = direction.flatMap { direction in
            Self.alignment(of: ahead.map(\.stopPointRef), in: direction).map { (direction, $0) }
        }
        let directionStops = alignment.map { Dictionary($0.0.stops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) } ?? [:]
        func stop(_ id: Foli.Stop.ID) -> Foli.Stop? { stops[id] ?? directionStops[id] }

        var calls: [Call] = []
        for passed in alignment.map({ $0.0.stops[..<$0.1.start] }) ?? [] {
            calls.append(Call(
                id: calls.count, stopID: passed.id, name: stop(passed.id)?.name ?? passed.name,
                coordinate: stop(passed.id)?.location ?? passed.location,
                expectedArrival: nil, aimedArrival: nil, state: .passed
            ))
        }
        let progress = vehicle.vehicleAtStop == true
            ? 1
            : min(1, max(0, (vehicle.segmentProgress ?? 0) / 100))
        nextStopIndex = ahead.isEmpty ? nil : calls.count
        for (offset, call) in ahead.enumerated() {
            calls.append(Call(
                id: calls.count, stopID: call.stopPointRef,
                name: stop(call.stopPointRef)?.name ?? call.stopPointName ?? call.stopPointRef,
                coordinate: stop(call.stopPointRef)?.location,
                expectedArrival: call.expectedArrivalTime.map(Date.init(timeIntervalSince1970:)),
                aimedArrival: call.aimedArrivalTime.map(Date.init(timeIntervalSince1970:)),
                state: offset == 0 ? .current(progress: progress) : .upcoming
            ))
        }
        self.calls = calls

        if let shape = alignment?.0.path, !shape.isEmpty {
            path = shape
            var start = 0
            for call in calls where call.state == .passed {
                guard let coordinate = call.coordinate,
                      let hit = shape.nearestSegment(to: coordinate, searchingFrom: start) else { continue }
                start = hit.index
            }
            pathSearchStart = start
        } else {
            path = calls.compactMap(\.coordinate)
            pathSearchStart = max(0, calls.prefix { $0.state == .passed }.compactMap(\.coordinate).count - 1)
        }
    }

    /// `path` split where the bus at `coordinate` projects onto it.
    public func splitPath(at coordinate: Foli.Coordinate) -> (travelled: [Foli.Coordinate], remaining: [Foli.Coordinate]) {
        path.split(at: coordinate, searchingFrom: pathSearchStart)
    }

    /// The next stop and the onward calls as one list. `onwardCalls` leaves out
    /// the next stop, which the feed gives only in the `next…` fields.
    static func aheadCalls(of vehicle: Foli.VehicleLocation) -> [Foli.VehicleLocation.StopCall] {
        var onward = vehicle.onwardCalls ?? []
        guard let ref = vehicle.nextStopPointRef else { return onward }
        if onward.first?.stopPointRef == ref { onward.removeFirst() }
        let next = Foli.VehicleLocation.StopCall(
            stopPointRef: ref,
            stopPointName: vehicle.nextStopPointName,
            aimedArrivalTime: vehicle.nextAimedArrivalTime,
            expectedArrivalTime: vehicle.nextExpectedArrivalTime,
            aimedDepartureTime: vehicle.nextAimedDepartureTime,
            expectedDepartureTime: vehicle.nextExpectedDepartureTime
        )
        return [next] + onward
    }

    struct Alignment: Equatable {
        /// Index in the direction's stops of the next stop.
        let start: Int
        /// Share of upcoming stops found in order after `start`.
        let score: Double
        /// Direction stops passed over between matches; breaks ties on a loop,
        /// where an earlier pass can reach the same stops the long way round.
        let skipped: Int

        func isBetter(than other: Alignment?) -> Bool {
            guard let other else { return true }
            return score != other.score ? score > other.score : skipped < other.skipped
        }
    }

    /// The representative trip may be a variant, so a few upcoming stops may be
    /// missing from it; below this share it's a different pattern.
    static let minimumAlignmentScore = 0.8

    /// Best place in `direction` for the upcoming stops to start, matching them
    /// in order (skips allowed); nil below `minimumAlignmentScore`.
    static func alignment(of ahead: [Foli.Stop.ID], in direction: RouteDirection) -> Alignment? {
        guard let first = ahead.first else { return nil }
        let ids = direction.stops.map(\.id)
        var best: Alignment?
        for start in ids.indices where ids[start] == first {
            var matched = 0
            var cursor = start
            for id in ahead {
                guard cursor < ids.endIndex, let found = ids[cursor...].firstIndex(of: id) else { continue }
                matched += 1
                cursor = found + 1
            }
            let candidate = Alignment(
                start: start,
                score: Double(matched) / Double(ahead.count),
                skipped: cursor - start - matched
            )
            if candidate.isBetter(than: best) { best = candidate }
        }
        guard let best, best.score >= minimumAlignmentScore else { return nil }
        return best
    }
}

extension Collection where Element == RouteDirection {
    /// The direction the vehicle's upcoming stops follow, if any does closely
    /// enough. SIRI `directionRef` doesn't reliably map to GTFS `direction_id`.
    public func bestMatch(for vehicle: Foli.VehicleLocation) -> RouteDirection? {
        let ahead = VehicleJourney.aheadCalls(of: vehicle).map(\.stopPointRef)
        var best: (direction: RouteDirection, alignment: VehicleJourney.Alignment)?
        for direction in self {
            guard let alignment = VehicleJourney.alignment(of: ahead, in: direction),
                  alignment.isBetter(than: best?.alignment) else { continue }
            best = (direction, alignment)
        }
        return best?.direction
    }
}
