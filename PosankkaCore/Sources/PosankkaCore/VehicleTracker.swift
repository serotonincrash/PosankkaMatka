import Foundation
import FoliBusAPI

/// Live vehicles for one scope, smoothed between polls: each vehicle glides
/// from its previous polled position to the newest over one poll interval.
public struct VehicleTracker: Sendable {
    public enum Scope: Equatable, Sendable {
        /// Vehicles on a line. SIRI `lineRef` is the route's short name, not its id.
        case line(String)
        /// Vehicles whose next or a later call is this stop.
        case stop(Foli.Stop.ID)
        /// One run of one bus; see `tripStatus(at:)`.
        case trip(TripKey)
    }

    public struct Position: Identifiable, Sendable {
        public let vehicle: Foli.VehicleLocation
        public let coordinate: Foli.Coordinate
        public var id: String { vehicle.id }
    }

    public enum TripStatus: Sendable {
        /// No poll has included the bus yet.
        case pending
        case live(Position)
        /// Missing from recent polls; held at its last position within the grace period.
        case stale(Position, lastSeen: Date)
        /// Started another run, or vanished at its terminus.
        case ended
        /// Missing past the grace period mid-trip.
        case lost
    }

    private struct Sample: Sendable {
        var vehicle: Foli.VehicleLocation
        /// Nil when the vehicle just appeared.
        var from: Foli.Coordinate?
        var to: Foli.Coordinate
        var fetchedAt: Date
        var lastSeen: Date
    }

    public let scope: Scope
    public let interval: TimeInterval
    /// How long a vehicle missing from the feed stays drawn. Feed dropouts are
    /// brief; vehicles that leave the scope are dropped at once.
    public let grace: TimeInterval
    private var samples: [String: Sample] = [:]
    private var lastPoll: Date?
    /// Trip scope only: how the tracked run finished, once it has.
    private var outcome: TripStatus?

    public init(scope: Scope, interval: TimeInterval, grace: TimeInterval = 60) {
        self.scope = scope
        self.interval = interval
        self.grace = grace
    }

    /// Takes a full-network poll, keeping in-scope vehicles that have a position.
    public mutating func update(with vehicles: [Foli.VehicleLocation], at date: Date) {
        lastPoll = date
        var next: [String: Sample] = [:]
        var reported: Set<String> = []
        for vehicle in vehicles {
            guard let to = vehicle.location else { continue }
            reported.insert(vehicle.id)
            if case .trip(let key) = scope, vehicle.vehicleRef == key.vehicleRef, !Self.isSameRun(vehicle, key) {
                outcome = .ended
                continue
            }
            guard matches(vehicle) else { continue }
            next[vehicle.id] = Sample(vehicle: vehicle, from: samples[vehicle.id]?.to, to: to, fetchedAt: date, lastSeen: date)
        }
        for (id, sample) in samples where next[id] == nil && !reported.contains(id) {
            if date.timeIntervalSince(sample.lastSeen) < grace, !Self.isAtTerminus(sample.vehicle) {
                // Hold still: the glide finished, so `from` would only replay it.
                var held = sample
                held.from = nil
                next[id] = held
            } else if case .trip = scope, outcome == nil {
                outcome = Self.isAtTerminus(sample.vehicle) || Self.isApproachingTerminus(sample.vehicle) ? .ended : .lost
            }
        }
        if outcome != nil, case .trip = scope { next = [:] }
        samples = next
    }

    /// Positions at `date`. Progress caps at 1, so a late poll holds the last position.
    public func positions(at date: Date) -> [Position] {
        samples.values.map { position(of: $0, at: date) }
    }

    /// Nil unless the scope is `.trip`.
    public func tripStatus(at date: Date) -> TripStatus? {
        guard case .trip = scope else { return nil }
        if let outcome { return outcome }
        guard let sample = samples.values.first else { return .pending }
        let position = position(of: sample, at: date)
        return sample.lastSeen == lastPoll ? .live(position) : .stale(position, lastSeen: sample.lastSeen)
    }

    private func position(of sample: Sample, at date: Date) -> Position {
        guard let from = sample.from else {
            return Position(vehicle: sample.vehicle, coordinate: sample.to)
        }
        let progress = min(1, max(0, date.timeIntervalSince(sample.fetchedAt) / interval))
        let coordinate = Foli.Coordinate(
            latitude: from.latitude + (sample.to.latitude - from.latitude) * progress,
            longitude: from.longitude + (sample.to.longitude - from.longitude) * progress
        )
        return Position(vehicle: sample.vehicle, coordinate: coordinate)
    }

    private func matches(_ vehicle: Foli.VehicleLocation) -> Bool {
        switch scope {
        case .line(let lineRef):
            vehicle.lineRef == lineRef
        case .stop(let stopId):
            vehicle.nextStopPointRef == stopId
                || vehicle.onwardCalls?.contains { $0.stopPointRef == stopId } == true
        case .trip(let key):
            vehicle.vehicleRef == key.vehicleRef
        }
    }

    /// A key without an origin time (unknown at selection) matches on line alone.
    private static func isSameRun(_ vehicle: Foli.VehicleLocation, _ key: TripKey) -> Bool {
        guard vehicle.lineRef == key.lineRef else { return false }
        guard let origin = key.originAimedDepartureTime else { return true }
        return vehicle.originAimedDepartureTime == origin
    }

    /// No stops after the next one: heading for, or at, the last stop.
    private static func isApproachingTerminus(_ vehicle: Foli.VehicleLocation) -> Bool {
        vehicle.onwardCalls?.isEmpty ?? true
    }

    private static func isAtTerminus(_ vehicle: Foli.VehicleLocation) -> Bool {
        isApproachingTerminus(vehicle) && vehicle.vehicleAtStop == true
    }
}
