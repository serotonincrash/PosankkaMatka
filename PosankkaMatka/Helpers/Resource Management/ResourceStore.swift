//
//  ResourceStore.swift
//  PosankkaMatka
//
//  Created by sero on 17/7/26.
//

import Foundation
import Observation
import FoliBusUI

/// Observable owner of one async-loaded resource: state, error mapping, and
/// timestamps. The fetch is passed per call because `@FoliService` resolves
/// only once installed.
@MainActor
@Observable
final class ResourceStore<T> {
    typealias Fetch = @Sendable () async throws -> T

    private(set) var state: ResourceState<T> = .loading
    /// When the visible value was last fetched; failed refreshes leave it, so
    /// it describes the data's actual age.
    private(set) var lastUpdated: Date?
    /// Last fetch error — surfaced as a banner while a value stays visible;
    /// cleared on success.
    private(set) var lastError: Foli.APIError?

    /// Fetches only if not loaded (for `.task`, which re-runs on appear).
    func load(_ fetch: @escaping Fetch) async {
        if case .success = state { return }
        state = .loading
        lastError = nil
        await run(fetch)
    }

    /// Always fetches (for `.refreshable`); on failure keeps any loaded value in
    /// `state` and reports through `lastError`.
    func refresh(_ fetch: @escaping Fetch) async {
        await run(fetch)
    }

    /// Whether a fetch is in flight (covers polling and pull-to-refresh).
    private(set) var isRefreshing = false

    private func run(_ fetch: @escaping Fetch) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            state = .success(try await fetch())
            lastUpdated = Date()
            lastError = nil
        } catch is CancellationError {
            // View went away or the task was superseded — not a failure.
        } catch {
            let foliError = error as? Foli.APIError ?? .networkError(error)
            lastError = foliError
            // Full-screen failure only when nothing is loaded yet; a refresh
            // failure leaves the list up.
            if state.value == nil {
                state = .failure(foliError)
            }
        }
    }
}
