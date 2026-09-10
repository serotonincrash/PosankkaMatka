//
//  ResourceState.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import Foundation
import FoliBusUI

enum ResourceState<T> {
    case loading
    case success(T)
    case failure(Foli.APIError)
}

extension ResourceState {
    /// The loaded value, or `nil` unless in the `.success` state.
    var value: T? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}

extension ResourceState: Equatable where T: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): true
        case (.success(let a), .success(let b)): a == b
        // `Foli.APIError` wraps non-Equatable `any Error`, so failures compare
        // as equal-when-both-failed rather than by their underlying error.
        case (.failure, .failure): true
        default: false
        }
    }
}
