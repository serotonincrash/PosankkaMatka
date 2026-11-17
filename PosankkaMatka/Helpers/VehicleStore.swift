//
//  VehicleStore.swift
//  PosankkaMatka
//
//  Created by sero on 9/10/26.
//

import Foundation
import Observation
import FoliBusUI
import PosankkaCore

/// Polls live vehicle positions for the open card's scope. Failed polls keep
/// the last positions rather than clearing them.
@MainActor
@Observable
final class VehicleStore {
    /// Each poll is the whole network (~217 KB gzipped); the API allows 3 s.
    private static let pollSeconds: TimeInterval = 5

    private(set) var lastError: Foli.APIError?
    /// Suspends fetching (e.g. backgrounded) without dropping the scope.
    var isPaused = false

    private let client: FoliClient
    private var tracker: VehicleTracker?
    private var pollTask: Task<Void, Never>?

    init(client: FoliClient) {
        self.client = client
    }

    /// Starts or switches scope; no-op if already on it.
    func start(_ scope: VehicleTracker.Scope) {
        guard tracker?.scope != scope else { return }
        pollTask?.cancel()
        tracker = VehicleTracker(scope: scope, interval: Self.pollSeconds)
        pollTask = Task { await poll() }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        tracker = nil
        lastError = nil
    }

    func displayVehicles(at date: Date) -> [VehicleTracker.Position] {
        tracker?.positions(at: date) ?? []
    }

    private func poll() async {
        while !Task.isCancelled {
            if !isPaused {
                do {
                    let fetched = try await client.fetchVehicleLocations()
                    guard !Task.isCancelled else { return }
                    tracker?.update(with: fetched, at: Date())
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
}
