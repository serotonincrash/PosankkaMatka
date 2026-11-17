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
    }

    public struct Position: Identifiable, Sendable {
        public let vehicle: Foli.VehicleLocation
        public let coordinate: Foli.Coordinate
        public var id: String { vehicle.id }
    }

    private struct Sample: Sendable {
        var vehicle: Foli.VehicleLocation
        /// Nil when the vehicle just appeared.
        var from: Foli.Coordinate?
        var to: Foli.Coordinate
        var fetchedAt: Date
    }

    public let scope: Scope
    public let interval: TimeInterval
    private var samples: [String: Sample] = [:]

    public init(scope: Scope, interval: TimeInterval) {
        self.scope = scope
        self.interval = interval
    }

    /// Takes a full-network poll, keeping in-scope vehicles that have a position.
    public mutating func update(with vehicles: [Foli.VehicleLocation], at date: Date) {
        var next: [String: Sample] = [:]
        for vehicle in vehicles where matches(vehicle) {
            guard let to = vehicle.location else { continue }
            next[vehicle.id] = Sample(vehicle: vehicle, from: samples[vehicle.id]?.to, to: to, fetchedAt: date)
        }
        samples = next
    }

    /// Positions at `date`. Progress caps at 1, so a late poll holds the last position.
    public func positions(at date: Date) -> [Position] {
        samples.values.map { sample in
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
    }

    private func matches(_ vehicle: Foli.VehicleLocation) -> Bool {
        switch scope {
        case .line(let lineRef):
            vehicle.lineRef == lineRef
        case .stop(let stopId):
            vehicle.nextStopPointRef == stopId
                || vehicle.onwardCalls?.contains { $0.stopPointRef == stopId } == true
        }
    }
}
