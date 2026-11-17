import FoliBusAPI

extension Collection where Element == Foli.Arrival {
    /// The stop feed's entry for one run, matched like `trip(for:)`. A key
    /// without an origin time takes the line's soonest arrival.
    public func arrival(for key: TripKey) -> Foli.Arrival? {
        guard let origin = key.originAimedDepartureTime else {
            return filter { $0.lineRef == key.lineRef }.min { $0.expectedArrivalTime < $1.expectedArrivalTime }
        }
        return first { $0.lineRef == key.lineRef && $0.originAimedDepartureTime == origin }
    }
}
