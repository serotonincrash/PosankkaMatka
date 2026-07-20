//
//  SortState.swift
//  PosankkaMatka
//
//  Created by sero on 17/7/26.
//


enum SortState: Hashable, Codable {
    /// Filter stops out based on proximity in meters
    case proximity(Double)
    
    /// Show all stops
    case none
}
