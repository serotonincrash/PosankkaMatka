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
}
