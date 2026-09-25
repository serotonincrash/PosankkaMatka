//
//  PosankkaMatkaTests.swift
//  PosankkaMatkaTests
//
//  Created by sero on 6/4/26.
//

import Testing
import Foundation
@testable import PosankkaMatka

struct PosankkaMatkaTests {

    @Test func formattedIntervalBuckets() {
        let now = Date.now
        #expect(now.addingTimeInterval(10).formattedInterval(to: now) == "Now")
        #expect(now.addingTimeInterval(300).formattedInterval(to: now) == "5 min")
        #expect(now.addingTimeInterval(-300).formattedInterval(to: now) == "-5 min ago")
        // Whole hours render as clock time — the minute modulo must not wrap
        // them into "Now".
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        components.hour = 9
        components.minute = 30
        let departure = Calendar.current.date(from: components)!
        #expect(departure.formattedInterval(to: departure.addingTimeInterval(-2 * 3600)) == "09:30")
    }

    @Test func spokenArrivalBuckets() {
        let now = Date.now
        func arrival(_ offset: TimeInterval) -> String {
            spokenArrival(line: "32", destination: "Kauppatori",
                          departure: now.addingTimeInterval(offset))
        }
        #expect(arrival(10) == "Line 32 to Kauppatori, departing now")
        #expect(arrival(300) == "Line 32 to Kauppatori, in 5 minutes")
        #expect(arrival(60) == "Line 32 to Kauppatori, in 1 minute")
        #expect(arrival(-300) == "Line 32 to Kauppatori, 5 minutes ago")
        // Sub-minute past stays past-tense (never "in 0 minutes").
        #expect(arrival(-10).hasSuffix("ago"))
        // An hour or more out reads as clock time (exact clock is locale-set).
        #expect(arrival(2 * 3600).hasPrefix("Line 32 to Kauppatori, departing at"))
    }

}
