//
//  Double+Formatted.swift
//  PosankkaMatka
//
//  Created by sero on 10/4/26.
//

import Foundation

extension Double {
    func formatted(toDecimalPlaces places: Int) -> String {
        return String(format: "%.\(places)f", self)
    }
}
