import Foundation

/// How an arrival time reads: relative while near, clock time after.
public enum ETADisplay: Equatable, Sendable {
    case now
    case minutes(Int)
    case clock(Date)

    public static let relativeLimit: TimeInterval = 15 * 60

    /// Past times read as `.now`: the feed's estimate can lag a bus still at the stop.
    public init(arrival: Date, now: Date) {
        let interval = arrival.timeIntervalSince(now)
        if interval < 60 {
            self = .now
        } else if interval < Self.relativeLimit {
            self = .minutes(Int(interval / 60))
        } else {
            self = .clock(arrival)
        }
    }
}
