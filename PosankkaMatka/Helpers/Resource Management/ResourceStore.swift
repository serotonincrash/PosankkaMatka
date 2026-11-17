//
//  ResourceStore.swift
//  PosankkaMatka
//
//  Created by sero on 17/7/26.
//

import Foundation
import Observation
import FoliBusUI
import PosankkaCore

/// One async-loaded resource with its state, last error and fetch time.
@MainActor
@Observable
final class ResourceStore<T> {
    typealias Fetch = @Sendable () async throws -> T

    private(set) var state: ResourceState<T> = .loading
    /// Age of the shown value; failed refreshes don't touch it.
    private(set) var lastUpdated: Date?
    /// Cleared on success.
    private(set) var lastError: Foli.APIError?

    /// Fetches only if not yet loaded (`.task` re-runs on appear).
    func load(_ fetch: @escaping Fetch) async {
        if case .success = state { return }
        state = .loading
        lastError = nil
        await run(fetch)
    }

    /// Always fetches; a failure keeps the loaded value and sets `lastError`.
    func refresh(_ fetch: @escaping Fetch) async {
        await run(fetch)
    }

    private(set) var isRefreshing = false

    private func run(_ fetch: @escaping Fetch) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            state = .success(try await fetch())
            lastUpdated = Date()
            lastError = nil
        } catch is CancellationError {
        } catch {
            let foliError = error as? Foli.APIError ?? .networkError(error)
            lastError = foliError
            if state.value == nil {
                state = .failure(foliError)
            }
        }
    }
}
