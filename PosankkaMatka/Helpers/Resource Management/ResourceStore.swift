//
//  ResourceStore.swift
//  PosankkaMatka
//
//  Created by sero on 17/7/26.
//

import Observation
import FoliBusUI

/// A generic, observable owner of one async-loaded resource — `ResourceState`,
/// the fetch, and error mapping; no domain logic (the client handles caching and
/// dedup). The fetch is supplied per call because `@FoliService` only resolves
/// once installed, so views pass it from `.task`/`.refreshable`.
@MainActor
@Observable
final class ResourceStore<T> {
    typealias Fetch = @Sendable () async throws -> T

    private(set) var state: ResourceState<T> = .loading

    /// Fetches only if not loaded (for `.task`, which re-runs on appear).
    func load(_ fetch: @escaping Fetch) async {
        if case .success = state { return }
        await run(fetch, resetToLoading: true)
    }

    /// Always fetches (for `.refreshable`); keeps the current value on failure.
    func refresh(_ fetch: @escaping Fetch) async {
        await run(fetch, resetToLoading: false)
    }

    private func run(_ fetch: @escaping Fetch, resetToLoading: Bool) async {
        // Only blank to `.loading` when we have nothing to show; keep any
        // existing value visible on refresh (and on a re-entrant `load`).
        if resetToLoading, case .success = state {
            // Already have data; don't blank it.
        } else if resetToLoading {
            state = .loading
        }

        do {
            state = .success(try await fetch())
        } catch is CancellationError {
            // View went away or the task was superseded — not a failure.
        } catch {
            state = .failure(error as? Foli.APIError ?? .networkError(error))
        }
    }
}
