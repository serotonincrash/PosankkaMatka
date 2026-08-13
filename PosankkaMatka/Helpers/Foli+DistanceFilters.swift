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
    func filter(byDistance distance: Double, from location: CLLocation) -> [Element] {
        let filtered = self.filter { stop in
            if let stopLocationCoordinate = stop.location {
                let stopLocation = CLLocation(latitude: stopLocationCoordinate.latitude, longitude: stopLocationCoordinate.longitude)
                return stopLocation.distance(from: location).isLess(than: distance)
            } else {
                return false
            }
        }
        return filtered
    }
    
    func sortedByDistance(to location: CLLocation) -> [Element] {
        let sorted = self.sorted { (s1, s2) in
            if let s1 = s1.location?.toCLCoordinate(), let s2 = s2.location?.toCLCoordinate() {
                let stop1Loc = CLLocation(latitude: s1.latitude, longitude: s1.longitude)
                let stop2Loc = CLLocation(latitude: s2.latitude, longitude: s2.longitude)
                return location.distance(from: stop1Loc) < location.distance(from: stop2Loc)
            } else {
                return false
            }
        }
        return sorted
    }

    /// The stops nearest `location`, already carrying their distances, sorted
    /// nearest-first.
    ///
    /// Replaces the previous sort → filter → re-map chain, which measured every
    /// distance `O(n log n)` times (two fresh `CLLocation` objects per
    /// comparison). Here each stop's distance is computed **once**, then the
    /// result is sorted.
    ///
    /// Also well-ordered where the old comparator was not: `sortedByDistance(to:)`
    /// returns `false` for pairs involving a stop with no coordinate, which is not
    /// a strict weak ordering and left such stops in unpredictable positions.
    /// Stops without a coordinate are excluded outright — they have no distance to
    /// rank by, and the nearby list exists to answer "what's close to me".
    ///
    /// - Parameters:
    ///   - location: The reference point, normally the user's location.
    ///   - maxDistance: Optional cutoff in meters; stops beyond it are dropped.
    func nearest(
        to location: CLLocation,
        withinMeters maxDistance: Double? = nil
    ) -> [(stop: Element, distance: Double)] {
        var measured: [(stop: Element, distance: Double)] = []
        measured.reserveCapacity(underestimatedCount)
        for stop in self {
            guard let coordinate = stop.location?.toCLCoordinate(),
                  let stopLocation = CLLocation(coordinate) else { continue }
            let distance = stopLocation.distance(from: location)
            if let maxDistance, distance >= maxDistance { continue }
            measured.append((stop, distance))
        }
        return measured.sorted { $0.distance < $1.distance }
    }
}
