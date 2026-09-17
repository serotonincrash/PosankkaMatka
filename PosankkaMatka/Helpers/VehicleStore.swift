//
//  VehicleStore.swift
//  PosankkaMatka
//
//  Created by sero on 9/10/26.
//

import CoreLocation
import Observation
import FoliBusUI

/// A vehicle paired with the coordinate to draw it at right now — the store's
/// blend of its two most recent polled positions.
struct DisplayedVehicle: Identifiable {
    let vehicle: Foli.VehicleLocation
    let coordinate: CLLocationCoordinate2D
    var id: String { vehicle.id }
}

/// SIRI VM vehicle positions, polled while a detail card is open. Each fetch
/// returns the whole network (no server-side filtering); the scope keeps the
/// relevant ones. Between polls, each vehicle interpolates linearly from its
/// previous position toward the newest one across the poll interval, so pucks
/// glide continuously instead of hopping every poll. Failed polls keep the
/// last samples (freeze, not wipe).
@MainActor
@Observable
final class VehicleStore {
    /// What the poller keeps from each full-network fetch.
    enum Scope: Equatable {
        /// Vehicles serving one line (`lineRef` == the route's short name,
        /// NOT its internal id).
        case line(String)
        /// Vehicles whose next stop is this one, or that will call at it later
        /// in their trip (`onwardCalls`).
        case stop(Foli.Stop.ID)
    }

    /// The API floor is 3 s and each poll is the whole network (~217 KB
    /// gzipped); 5 s trades a little freshness for bandwidth.
    private static let pollSeconds: TimeInterval = 5

    private struct Sample {
        var vehicle: Foli.VehicleLocation
        /// Where the previous poll drew it; nil when it just appeared.
        var from: CLLocationCoordinate2D?
        var to: CLLocationCoordinate2D
        var fetchedAt: Date
    }

    private(set) var lastError: Foli.APIError?
    /// Suspends fetching (e.g. backgrounded) without dropping the scope.
    var isPaused = false

    private var scope: Scope?
    private var samples: [String: Sample] = [:]   // keyed by vehicleRef
    private var pollTask: Task<Void, Never>?

    /// Starts (or switches to) a scope; no-op when already monitoring it.
    func start(_ scope: Scope, using foli: FoliService) {
        guard self.scope != scope else { return }
        self.scope = scope
        pollTask?.cancel()
        samples = [:]   // never show the old scope's vehicles mid-switch
        pollTask = Task {
            await poll(scope, using: foli)
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        scope = nil
        samples = [:]
        lastError = nil
    }

    /// The scoped vehicles at `date`, each gliding from its previous polled
    /// position toward the newest one over one poll interval (progress caps at
    /// 1, so a slow next poll just holds the last position).
    func displayVehicles(at date: Date) -> [DisplayedVehicle] {
        samples.map { _, sample in
            let coordinate: CLLocationCoordinate2D
            if let from = sample.from {
                let progress = min(1, max(0, date.timeIntervalSince(sample.fetchedAt) / Self.pollSeconds))
                coordinate = CLLocationCoordinate2D(
                    latitude: from.latitude + (sample.to.latitude - from.latitude) * progress,
                    longitude: from.longitude + (sample.to.longitude - from.longitude) * progress
                )
            } else {
                coordinate = sample.to
            }
            return DisplayedVehicle(vehicle: sample.vehicle, coordinate: coordinate)
        }
    }

    private func poll(_ scope: Scope, using foli: FoliService) async {
        while !Task.isCancelled {
            if !isPaused {
                do {
                    // VM is never disk-cached; every poll is fresh. Positionless
                    // vehicles are omitted by the package (2.3.0) and skipped
                    // here too — only displayable positions become samples.
                    let fetched = try await foli.fetchVehicleLocations()
                        .filter { matches($0, scope: scope) }
                    let now = Date()
                    var next: [String: Sample] = [:]
                    for vehicle in fetched {
                        guard let to = vehicle.location?.toCLCoordinate() else { continue }
                        next[vehicle.id] = Sample(
                            vehicle: vehicle,
                            from: samples[vehicle.id]?.to,
                            to: to,
                            fetchedAt: now
                        )
                    }
                    samples = next
                    lastError = nil
                } catch is CancellationError {
                    return
                } catch let error as Foli.APIError {
                    lastError = error
                } catch {
                    lastError = .networkError(error)
                }
            }
            try? await Task.sleep(for: .seconds(Self.pollSeconds))
        }
    }

    private func matches(_ vehicle: Foli.VehicleLocation, scope: Scope) -> Bool {
        switch scope {
        case .line(let lineRef):
            vehicle.lineRef == lineRef
        case .stop(let stopId):
            vehicle.nextStopPointRef == stopId
                || vehicle.onwardCalls?.contains { $0.stopPointRef == stopId } == true
        }
    }
}
