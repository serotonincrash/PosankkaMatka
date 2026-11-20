//
//  StopAlertAttributes.swift
//  PosankkaMatka
//
//  Shared with the widget extension: Foundation and ActivityKit only.
//

import ActivityKit
import Foundation

/// One bus reaching the stop the rider chose, and how far the rider is from
/// it. Updated by the app while its background location session runs.
nonisolated struct StopAlertAttributes: ActivityAttributes, Hashable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Last-known expected arrival at the alert stop.
        var eta: Date
        /// When `eta` was read; also the countdown's lower bound.
        var updatedAt: Date
        var nextStopName: String?
        /// The rider's own location reached the stop.
        var hasArrived: Bool = false
        /// The bus reached the stop or left its feed; the session is over.
        var busPassed: Bool = false
        /// Device to stop, straight line; nil without a fix.
        var distanceMeters: Double?
        /// Walk to the stop, with the street detour; nil without a fix.
        var walkingMinutes: Int?

        /// The countdown no longer means much once the estimate has gone
        /// unrefreshed for a while.
        var estimateExpiry: Date { updatedAt.addingTimeInterval(600) }

        /// At the ETA too, so the widget re-renders and swaps the finished
        /// countdown for "Now".
        var staleDate: Date { min(eta, estimateExpiry) }
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
