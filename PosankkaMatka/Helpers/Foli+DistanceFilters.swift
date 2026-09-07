//
//  Foli+DistanceFilters.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import FoliBusAPI
import Foundation
import CoreLocation
extension Collection where Element == Foli.Stop {
    /// The stops nearest to `location`, with distances, sorted nearest-first. Each
    /// distance is computed once; stops without a coordinate are excluded.
    func nearest(
        to location: CLLocation,
        withinMeters maxDistance: Double? = nil
    ) -> [(stop: Element, distance: Double)] {
        var measured: [(stop: Element, distance: Double)] = []
        measured.reserveCapacity(underestimatedCount)
        for stop in self {
            guard let coordinate = stop.location?.toCLCoordinate(),
                  CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let stopLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = stopLocation.distance(from: location)
            if let maxDistance, distance >= maxDistance { continue }
            measured.append((stop, distance))
        }
        return measured.sorted { $0.distance < $1.distance }
    }
}
