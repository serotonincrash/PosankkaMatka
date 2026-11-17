import FoliBusAPI

extension Collection where Element == Foli.VehicleLocation {
    /// The live run serving `arrival`; nil before the bus is live. Monitored
    /// arrivals name their vehicle; otherwise line plus planned origin
    /// departure names one run.
    public func trip(for arrival: Foli.Arrival) -> TripKey? {
        if let vehicleRef = arrival.vehicleRef,
           let vehicle = first(where: { $0.vehicleRef == vehicleRef }),
           vehicle.lineRef == arrival.lineRef,
           vehicle.originAimedDepartureTime == arrival.originAimedDepartureTime {
            return TripKey(vehicle)
        }
        return first {
            $0.lineRef == arrival.lineRef
                && $0.originAimedDepartureTime == arrival.originAimedDepartureTime
        }
        .map(TripKey.init)
    }
}
