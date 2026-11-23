//
//  PosankkaMatkaUITests.swift
//  PosankkaMatkaUITests
//
//  Created by sero on 6/4/26.
//

import XCTest

final class PosankkaMatkaUITests: XCTestCase {

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
