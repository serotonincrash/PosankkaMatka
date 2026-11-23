//
//  LocationManager.swift
//  PosankkaMatka
//
//  Created by sero on 7/4/26.
//

import Foundation
import CoreLocation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate  {
    var currentLocation: CLLocationCoordinate2D?

    private(set) var isAuthorized: Bool = false

    @ObservationIgnored
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.activityType = .otherNavigation
        self.locationManager.distanceFilter = 5
        self.locationManager.requestWhenInUseAuthorization()
        refreshAuthorization()
    }

    private func refreshAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            if currentLocation == nil {
                currentLocation = locationManager.location?.coordinate
            }
            locationManager.startUpdatingLocation()
        default:
            isAuthorized = false
            locationManager.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ locationManager: CLLocationManager) {
        refreshAuthorization()
    }

    func locationManager(_ locationManager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }
}
