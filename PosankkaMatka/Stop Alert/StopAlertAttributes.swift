//
//  StopAlertAttributes.swift
//  PosankkaMatka
//
//  Shared with the widget extension: Foundation and ActivityKit only.
//

import ActivityKit
import Foundation

/// A countdown to one bus reaching the stop the rider chose. No server
/// pushes, so the state is only as fresh as the app's last foreground poll.
nonisolated struct StopAlertAttributes: ActivityAttributes, Hashable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Last-known expected arrival at the alert stop.
        var eta: Date
        /// When `eta` was read; also the countdown's lower bound.
        var updatedAt: Date
        var nextStopName: String?
        /// Positive is late.
        var delaySeconds: Int?
        /// The rider's own location reached the stop.
        var hasArrived: Bool = false

        /// The countdown no longer means much past the ETA, nor once the
        /// estimate has gone unrefreshed for a while.
        var staleDate: Date {
            min(eta.addingTimeInterval(120), updatedAt.addingTimeInterval(600))
        }
    }

    /// Published line name, e.g. "15".
    var lineName: String
    /// GTFS `route_color` / `route_text_color`, without a leading #.
    var lineColorHex: String?
    var lineTextColorHex: String?
    var destinationName: String?

    var stopID: String
    var stopName: String

    // TripKey, flattened: the widget doesn't link PosankkaCore.
    var vehicleRef: String
    var lineRef: String
    var originAimedDepartureTime: TimeInterval?
}
