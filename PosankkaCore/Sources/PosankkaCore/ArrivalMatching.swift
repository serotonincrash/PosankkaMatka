import FoliBusAPI

extension Collection where Element == Foli.VehicleLocation {
    /// The live run serving `arrival`. Arrivals carry no vehicle ref, but line
    /// plus planned origin departure names one run; nil before the bus is live.
    public func trip(for arrival: Foli.Arrival) -> TripKey? {
        first {
            $0.lineRef == arrival.lineRef
                && $0.originAimedDepartureTime == arrival.originAimedDepartureTime
        }
        .map(TripKey.init)
    }
}
