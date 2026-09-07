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
    /// The last fetch error, kept alongside any still-visible value so a failed
    /// refresh can surface a banner instead of wiping the list. Cleared on success.
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

    private func run(_ fetch: @escaping Fetch) async {
        do {
            state = .success(try await fetch())
            lastError = nil
        } catch is CancellationError {
            // View went away or the task was superseded — not a failure.
        } catch {
            let foliError = error as? Foli.APIError ?? .networkError(error)
            lastError = foliError
            // Full-screen failure only when there is no value to preserve
            // (an initial load); a refresh failure leaves the list up.
            if state.value == nil {
                state = .failure(foliError)
            }
        }
    }
}
