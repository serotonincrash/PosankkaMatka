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

}
