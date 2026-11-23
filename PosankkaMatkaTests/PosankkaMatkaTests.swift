//
//  PosankkaMatkaTests.swift
//  PosankkaMatkaTests
//
//  Created by sero on 6/4/26.
//

import Testing
import Foundation
import PosankkaCore
@testable import PosankkaMatka

struct PosankkaMatkaTests {

    @Test func spokenETABuckets() {
        let now = Date.now
        func spoken(_ offset: TimeInterval) -> String {
            ETADisplay(arrival: now.addingTimeInterval(offset), now: now).spoken
        }
        #expect(spoken(10) == "arriving now")
        // A just-departed bus may still be at the stop: never "ago".
        #expect(spoken(-300) == "arriving now")
        #expect(spoken(300) == "in 5 minutes")
        // Past the relative window, clock time (exact clock is locale-set).
        #expect(spoken(20 * 60).hasPrefix("at "))
    }

}
