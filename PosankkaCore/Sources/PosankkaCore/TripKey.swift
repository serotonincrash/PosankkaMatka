import Foundation
import FoliBusAPI

/// One run of one bus. `vehicleRef` alone names the physical bus, which starts
/// a new trip at the terminus; the planned origin departure tells runs apart.
public struct TripKey: Hashable, Sendable {
    public let vehicleRef: String
    public let lineRef: String
    public let originAimedDepartureTime: TimeInterval?

    public init(vehicleRef: String, lineRef: String, originAimedDepartureTime: TimeInterval?) {
        self.vehicleRef = vehicleRef
        self.lineRef = lineRef
        self.originAimedDepartureTime = originAimedDepartureTime
    }

    public init(_ vehicle: Foli.VehicleLocation) {
        self.init(
            vehicleRef: vehicle.vehicleRef,
            lineRef: vehicle.lineRef,
            originAimedDepartureTime: vehicle.originAimedDepartureTime
        )
    }
}
