//
//  ResourceStore.swift
//  PosankkaMatka
//
//  Created by sero on 17/7/26.
//

import Observation
import FoliBusUI

/// A generic, observable owner of one async-loaded resource.
///
/// The store owns three things: the ``ResourceState``, the fetch operation, and
/// the error mapping. It intentionally owns no domain logic — no filtering,
/// sorting, caching, or request deduplication. FoliBusAPI's client already
/// deduplicates concurrent identical requests (`FoliDedup`), so the store stays
/// a thin UI-state adapter.
///
/// The fetch operation is supplied per call rather than at `init`, because
/// `@FoliService` only resolves its client once installed in the view
/// hierarchy — so views pass the fetch from within `.task`/`.refreshable`,
/// where `foli` is valid.
@MainActor
@Observable
final class ResourceStore<T> {
    typealias Fetch = @Sendable () async throws -> T

    private(set) var state: ResourceState<T> = .loading

    /// Fetches only if not already loaded. Intended for `.task`, which re-runs
    /// each time a view appears — an already-loaded resource is not re-fetched.
    func load(_ fetch: @escaping Fetch) async {
        if case .success = state { return }
        await run(fetch, resetToLoading: true)
    }

    /// Always fetches, keeping any current value visible while it runs.
    /// Intended for `.refreshable`. A failed refresh preserves existing data.
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
