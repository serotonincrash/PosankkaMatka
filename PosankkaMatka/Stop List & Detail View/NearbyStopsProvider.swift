//
//  NearbyStopsProvider.swift
//  PosankkaMatka
//
//  Created by sero on 7/25/26.
//

import CoreLocation
import Observation
import FoliBusUI

/// Computes nearby rows off the `body` path, only when an input changes;
/// `recompute` is explicit so callers control when it runs.
@MainActor
@Observable
final class NearbyStopsProvider {
    /// The finished rows, nearest first. Read by the view; never computed in `body`.
    private(set) var rows: [StopWithDistance] = []

    /// Inputs that produced `rows`, used to skip redundant work.
    private var lastStopCount: Int?
    private var lastFilter: SortState?
    private var lastCoordinate: CLLocationCoordinate2D?

    /// Recomputes `rows` when an input changed.
    func recompute(
        stops: [Foli.Stop],
        coordinate: CLLocationCoordinate2D?,
        filter: SortState
    ) {
        guard needsRecompute(stopCount: stops.count, coordinate: coordinate, filter: filter) else {
            return
        }
        lastStopCount = stops.count
        lastFilter = filter
        lastCoordinate = coordinate

        // No usable location: nearby is undefined. Surface nothing and let the
        // view disclose the state — it tracks authorization separately.
        guard let coordinate, let origin = CLLocation(coordinate) else {
            rows = []
            return
        }

        let maxDistance: Double? = if case .proximity(let meters) = filter, meters > 0 {
            meters
        } else {
            nil
        }
        rows = stops
            .nearest(to: origin, withinMeters: maxDistance)
            .map { StopWithDistance($0.stop, distance: $0.distance) }
    }

    private func needsRecompute(
        stopCount: Int,
        coordinate: CLLocationCoordinate2D?,
        filter: SortState
    ) -> Bool {
        if lastStopCount != stopCount || lastFilter != filter { return true }
        switch (lastCoordinate, coordinate) {
        case (nil, nil):
            return false
        case (let previous?, let next?):
            // Ignore sub-meter jitter; ~1e-5 degrees is close enough to a meter
            // that re-sorting the list would be churn for no visible change.
            return abs(previous.latitude - next.latitude) > 0.00001
                || abs(previous.longitude - next.longitude) > 0.00001
        default:
            return true
        }
    }
}
