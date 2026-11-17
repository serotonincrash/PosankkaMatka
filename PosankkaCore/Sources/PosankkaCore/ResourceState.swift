import FoliBusAPI

public enum ResourceState<T> {
    case loading
    case success(T)
    case failure(Foli.APIError)
}

extension ResourceState {
    /// The loaded value, if any.
    public var value: T? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}

extension ResourceState: Equatable where T: Equatable {
    /// Failures compare equal regardless of error: `Foli.APIError` wraps a
    /// non-Equatable `any Error`.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): true
        case (.success(let a), .success(let b)): a == b
        case (.failure, .failure): true
        default: false
        }
    }
}
