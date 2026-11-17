//
//  Double+FormattedDistance.swift
//  PosankkaMatka
//

import Foundation

extension Double {
    /// "850 m" or "1.23 km".
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }
}
