//
//  Foli+RouteSorting.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import Foundation
import FoliBusAPI

extension Foli.Route {
    /// Row label for screen readers ("Route 15, Kauppatori–Länsikeskus").
    var spokenDescription: String {
        "Route \(shortName), \(longName)"
    }
}

extension Collection where Element == Foli.Route {
    /// Sorts by the leading integer of `shortName` (full string as tiebreaker);
    /// non-numeric names sort last, alphabetically.
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
