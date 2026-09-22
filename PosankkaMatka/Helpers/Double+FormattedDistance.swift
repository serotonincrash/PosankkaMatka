//
//  Double+FormattedDistance.swift
//  PosankkaMatka
//

import Foundation

extension Double {
    /// "850 m" / "1.23 km" — metres switch to kilometres past 1 km, with
    /// adaptive decimals.
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }
}
