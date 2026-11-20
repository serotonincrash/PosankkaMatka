import Foundation
import Testing
import FoliBusAPI
@testable import PosankkaCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func input(
    at offset: TimeInterval = 0, eta: TimeInterval? = 600, missing: Bool = false,
    distance: Double? = 2_000, speed: Double? = 0, sent: Set<StopAlertPolicy.Alert> = []
) -> StopAlertPolicy.Input {
    StopAlertPolicy.Input(
        now: t0.addingTimeInterval(offset), sessionStart: t0,
        busETA: eta.map { t0.addingTimeInterval($0) }, busMissingFromFeed: missing,
        distance: distance, speed: speed, sent: sent
    )
}

@Test func walkingTimeAddsDetour() {
    #expect(StopAlertPolicy.walkingTime(forDistance: 130) == 130)
}

@Test func farAwayWithTimeToSpareDoesNothing() {
    // 300 m → 300 s walk + 60 s buffer < 600 s until the bus.
    #expect(StopAlertPolicy.evaluate(input(distance: 300)) == .init())
}

@Test func leaveNowWhenWalkPlusBufferCoversTheWait() {
    // 500 m → 500 s walk + 60 s ≥ 540 s until the bus.
    let outcome = StopAlertPolicy.evaluate(input(at: 60, distance: 500))
    #expect(outcome.notify == .leaveNow)
    #expect(outcome.end == nil)
}

@Test func leaveNowFiresOnce() {
    #expect(StopAlertPolicy.evaluate(input(at: 60, distance: 500, sent: [.leaveNow])).notify == nil)
}

@Test func atStopWaitsForBusArriving() {
    #expect(StopAlertPolicy.evaluate(input(distance: 40)).notify == nil)
    #expect(StopAlertPolicy.evaluate(input(at: 500, distance: 40)).notify == .busArriving)
    #expect(StopAlertPolicy.evaluate(input(at: 500, distance: 40, sent: [.busArriving])).notify == nil)
}

@Test func ridingCloseToStopNotifiesAndEnds() {
    let outcome = StopAlertPolicy.evaluate(input(distance: 350, speed: 9))
    #expect(outcome == .init(notify: .stopIsNext, end: .arrived))
}

@Test func ridingFarFromStopSuppressesLeaveNow() {
    #expect(StopAlertPolicy.evaluate(input(at: 590, distance: 2_000, speed: 9)) == .init())
}

@Test func busPastItsETAEndsTheSession() {
    #expect(StopAlertPolicy.evaluate(input(at: 600 + 121, distance: 40)).end == .busPassed)
    #expect(StopAlertPolicy.evaluate(input(at: 600 + 60, distance: 40)).end == nil)
}

@Test func busMissingFromFeedEndsTheSession() {
    #expect(StopAlertPolicy.evaluate(input(missing: true)).end == .busPassed)
}

@Test func sessionTimesOutAfterAnHour() {
    #expect(StopAlertPolicy.evaluate(input(at: 3_600, eta: 4_000)).end == .timedOut)
}

@Test func tooFarToCatchTheBusSkipsLeaveNow() {
    // 1 km → 1000 s walk > 600 s until the bus.
    #expect(StopAlertPolicy.evaluate(input(distance: 1_000)) == .init())
}

@Test func busArrivingFiresAwayFromTheStop() {
    #expect(StopAlertPolicy.evaluate(input(at: 500, distance: 2_000)).notify == .busArriving)
}

@Test func noFixStillAnnouncesTheBus() {
    #expect(StopAlertPolicy.evaluate(input(at: 300, distance: nil)) == .init())
    #expect(StopAlertPolicy.evaluate(input(at: 590, distance: nil)).notify == .busArriving)
}

@Test func noETAYetDoesNothingUnlessRiding() {
    #expect(StopAlertPolicy.evaluate(input(eta: nil, distance: 500)) == .init())
    #expect(StopAlertPolicy.evaluate(input(eta: nil, distance: 300, speed: 8)).notify == .stopIsNext)
}

private func arrival(line: String, origin: TimeInterval, expected: TimeInterval) -> Foli.Arrival {
    Foli.Arrival(
        recordedAtTime: 0, lineRef: line, monitored: true, originAimedDepartureTime: origin,
        destinationAimedArrivalTime: 0, destinationDisplay: "", aimedArrivalTime: expected,
        expectedArrivalTime: expected, aimedDepartureTime: expected, expectedDepartureTime: expected
    )
}

@Test func stopFeedMatchesTheRunByLineAndOrigin() {
    let feed = [arrival(line: "15", origin: 100, expected: 900), arrival(line: "15", origin: 200, expected: 1_500),
                arrival(line: "7", origin: 200, expected: 300)]
    let key = TripKey(vehicleRef: "v", lineRef: "15", originAimedDepartureTime: 200)
    #expect(feed.arrival(for: key)?.expectedArrivalTime == 1_500)
    let unknownOrigin = TripKey(vehicleRef: "v", lineRef: "15", originAimedDepartureTime: nil)
    #expect(feed.arrival(for: unknownOrigin)?.expectedArrivalTime == 900)
    #expect(feed.arrival(for: TripKey(vehicleRef: "v", lineRef: "3", originAimedDepartureTime: 1)) == nil)
}
