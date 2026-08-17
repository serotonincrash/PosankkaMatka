//
//  SortState.swift
//  PosankkaMatka
//
//  Created by sero on 17/7/26.
//


/// The distance cutoff for the idle "Nearby Stops" list.
enum SortState: Hashable, Codable {
    /// Only stops within this many meters of the user.
    case proximity(Double)
    
    /// No distance cutoff — every stop, nearest first.
    case none
}
