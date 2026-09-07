//
//  Date+formattedInterval.swift
//  PosankkaMatka
//
//  Created by sero on 21/4/26.
//

import Foundation
extension Date {
    /// "Now" (under half a minute out), "N min" / "N min ago", or "HH:mm" an
    /// hour or more out.
    func formattedInterval(to date: Date) -> String {
        let interval = timeIntervalSince(date)
        let minutes = Int((interval / 60).rounded())
        if interval <= 0 {
            return "\(minutes) min ago"
        } else if minutes >= 60 {
            return Self.timeFormatter.string(from: self)
        } else {
            return minutes == 0 ? "Now" : "\(minutes) min"
        }
    }

    /// Created once — `DateFormatter` allocation is expensive enough to matter
    /// per-row.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
