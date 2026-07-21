//
//  Foli+RouteSorting.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import Foundation
import FoliBusAPI

extension Collection where Element == Foli.Route {
    /// Sorts routes by line number the way riders read them: 1, 2, 2a, 15, 100 —
    /// primarily by the leading integer of `shortName`, with the full string as a
    /// tiebreaker (so "2" precedes "2a"). Routes whose `shortName` has no leading
    /// digits sort after numbered ones, alphabetically.
    func sortedByLine() -> [Foli.Route] {
        sorted { lhs, rhs in
            let l = Self.leadingNumber(lhs.shortName)
            let r = Self.leadingNumber(rhs.shortName)
            switch (l, r) {
            case let (l?, r?) where l != r: return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.shortName.localizedStandardCompare(rhs.shortName) == .orderedAscending
            }
        }
    }

    private static func leadingNumber(_ s: String) -> Int? {
        Int(s.prefix { $0.isNumber })
    }
}
