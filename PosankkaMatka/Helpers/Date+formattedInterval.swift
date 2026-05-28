//
//  Date+formattedInterval.swift
//  PosankkaMatka
//
//  Created by sero on 21/4/26.
//

import Foundation
extension Date {
    
    // thank you random stackoverflow answer
    static func - (lhs: Date, rhs: Date) -> TimeInterval {
            return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }
    
    func formattedInterval(to date: Date) -> String {
        let interval = self - date
        let minutes = interval / 60
        let hours = Int(interval) / 3600
        let negative = interval <= 0
        let roundedMinutes = Int(minutes.rounded()) % 60
        // if the rounded minutes are <= 0 and the time interval isn't negative then it's ~0 minutes
        // if it's negative then the thing happened in the past, display "ago" in formatted string
        // if its more than 1 hour just display the time
        // and finally just return the amount of rounded minutes
        if (roundedMinutes <= 0 && !negative) {
            return "Now"
        } else if negative {
            return "\(roundedMinutes) min ago"
        } else if hours > 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: self)
        } else {
            return "\(roundedMinutes) min"
        }
    }
}
