import Foundation

/// When an "Alert Me Here" session notifies, and when it ends. Pure: the app
/// feeds it the bus ETA from the stop feed and the device's own location.
public enum StopAlertPolicy {
    public enum Alert: String, Codable, Sendable, CaseIterable {
        /// Away from the stop, and walking there now only just makes the bus.
        case leaveNow
        /// Waiting at the stop and the bus is about to arrive.
        case busArriving
        /// Riding the bus and the stop is close.
        case stopIsNext
    }

    public enum EndReason: Equatable, Sendable {
        /// The bus reached the stop, or the trip left the stop's feed.
        case busPassed
        /// The rider's own stop came up while riding.
        case arrived
        case timedOut
    }

    public struct Input: Sendable {
        public var now: Date
        public var sessionStart: Date
        /// Latest expected arrival at the stop; nil if never read.
        public var busETA: Date?
        /// The trip has dropped out of the stop's feed (confirmed, not a single miss).
        public var busMissingFromFeed: Bool
        /// Device to stop, straight line; nil without a fix.
        public var distance: Double?
        /// Device speed in m/s; nil or negative when unknown.
        public var speed: Double?
        public var sent: Set<Alert>

        public init(
            now: Date, sessionStart: Date, busETA: Date?, busMissingFromFeed: Bool = false,
            distance: Double?, speed: Double?, sent: Set<Alert> = []
        ) {
            self.now = now
            self.sessionStart = sessionStart
            self.busETA = busETA
            self.busMissingFromFeed = busMissingFromFeed
            self.distance = distance
            self.speed = speed
            self.sent = sent
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var notify: Alert?
        public var end: EndReason?
    }

    // Tuning, in one place.
    /// Streets aren't straight lines.
    public static let detourFactor = 1.3
    /// m/s, an unhurried walk.
    public static let walkingSpeed = 1.3
    /// Slack on top of the walk for "Leave now".
    public static let leaveBuffer: TimeInterval = 60
    /// Within this of the stop counts as waiting there.
    public static let atStopRadius: Double = 100
    /// "Bus arriving" when it's at most this far out.
    public static let arrivingWindow: TimeInterval = 120
    /// ~18 km/h: faster than walking or jogging, so on the bus (or a bike).
    public static let ridingSpeed: Double = 5
    /// "Your stop is next" range while riding; about one stop spacing.
    public static let nextStopRadius: Double = 400
    /// The bus counts as gone this long after its ETA.
    public static let passedGrace: TimeInterval = 120
    public static let maxDuration: TimeInterval = 60 * 60

    /// Walking time for a straight-line distance.
    public static func walkingTime(forDistance distance: Double) -> TimeInterval {
        distance * detourFactor / walkingSpeed
    }

    public static func evaluate(_ input: Input) -> Outcome {
        if input.now.timeIntervalSince(input.sessionStart) >= maxDuration {
            return Outcome(end: .timedOut)
        }
        if input.busMissingFromFeed {
            return Outcome(end: .busPassed)
        }
        if let eta = input.busETA, input.now.timeIntervalSince(eta) > passedGrace {
            return Outcome(end: .busPassed)
        }
        guard let distance = input.distance else { return Outcome() }

        let riding = (input.speed ?? 0) >= ridingSpeed
        if riding {
            // Riding: the stop's arrival time doesn't matter, only being close.
            if distance <= nextStopRadius, !input.sent.contains(.stopIsNext) {
                return Outcome(notify: .stopIsNext, end: .arrived)
            }
            return Outcome()
        }
        guard let eta = input.busETA else { return Outcome() }
        let untilBus = eta.timeIntervalSince(input.now)

        if distance <= atStopRadius {
            if untilBus <= arrivingWindow, !input.sent.contains(.busArriving) {
                return Outcome(notify: .busArriving)
            }
            return Outcome()
        }
        if untilBus > 0,
           walkingTime(forDistance: distance) + leaveBuffer >= untilBus,
           !input.sent.contains(.leaveNow) {
            return Outcome(notify: .leaveNow)
        }
        return Outcome()
    }
}
