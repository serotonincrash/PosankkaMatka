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
    /// The most recent coordinate (observable; `distanceFilter` bounds updates).
    var currentLocation: CLLocationCoordinate2D?

    /// Authorization mirrored into observable state by the delegate.
    private(set) var isAuthorized: Bool = false

    /// Not observable — reading its mutable state from `body` registers spurious dependencies.
    @ObservationIgnored
    var locationManager: CLLocationManager = CLLocationManager()

    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.activityType = .otherNavigation
        self.locationManager.distanceFilter = 5
        self.locationManager.requestWhenInUseAuthorization()
        // Seed from the current status; the delegate keeps it current afterward.
        refreshAuthorization()
    }

    /// Recomputes `isAuthorized` from the system status and starts or stops
    /// location updates to match.
    private func refreshAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            if currentLocation == nil {
                currentLocation = locationManager.location?.coordinate
            }
            locationManager.startUpdatingLocation()
        case .notDetermined, .restricted, .denied:
            isAuthorized = false
            locationManager.stopUpdatingLocation()
        @unknown default:
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
