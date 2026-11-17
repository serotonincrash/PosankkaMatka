import Foundation
import Testing
import FoliBusAPI
@testable import PosankkaCore

private func stop(_ id: String, lat: Double = 0, lon: Double = 0) -> Foli.Stop {
    Foli.Stop(id: id, name: "Stop \(id)", latitude: lat, longitude: lon)
}

private func direction(_ id: Int, _ stopIDs: [String], path: [Foli.Coordinate] = []) -> RouteDirection {
    RouteDirection(
        id: id, headsign: "H\(id)",
        stops: stopIDs.enumerated().map { stop($1, lat: 0, lon: Double($0)) },
        path: path
    )
}

private func call(_ id: String, expected: TimeInterval? = nil) -> Foli.VehicleLocation.StopCall {
    .init(stopPointRef: id, stopPointName: "SIRI \(id)", aimedArrivalTime: expected, expectedArrivalTime: expected)
}

private func bus(
    _ ref: String = "v1", line: String = "15", origin: TimeInterval? = 1000,
    next: String? = nil, onward: [String] = [], atStop: Bool? = false,
    percentage: Double? = nil, lat: Double = 0, lon: Double = 0, delay: String? = nil
) -> Foli.VehicleLocation {
    Foli.VehicleLocation(
        recordedAtTime: 0, validUntilTime: 0, segmentProgress: percentage, lineRef: line,
        directionRef: "1", publishedLineName: line, operatorRef: "x",
        destinationName: "Terminus", originAimedDepartureTime: origin,
        monitored: true, inCongestion: false, inPanic: false,
        longitude: lon, latitude: lat, delay: delay, vehicleRef: ref,
        vehicleAtStop: atStop, nextStopPointRef: next, nextStopPointName: next.map { "SIRI \($0)" },
        nextExpectedArrivalTime: next == nil ? nil : 100,
        onwardCalls: onward.map { call($0, expected: 200) }
    )
}

// MARK: - Journey

@Test func journeyPrependsPassedStopsFromMatchedDirection() {
    let journey = VehicleJourney(
        vehicle: bus(next: "C", onward: ["D", "E"], percentage: 40, delay: "PT120S"),
        direction: direction(0, ["A", "B", "C", "D", "E"])
    )
    #expect(journey.calls.map(\.stopID) == ["A", "B", "C", "D", "E"])
    #expect(journey.calls.map(\.state) == [.passed, .passed, .current(progress: 0.4), .upcoming, .upcoming])
    #expect(journey.calls.map(\.id) == [0, 1, 2, 3, 4])
    #expect(journey.nextStopIndex == 2)
    #expect(journey.terminus?.stopID == "E")
    #expect(journey.delay == 120)
    #expect(journey.destinationName == "Terminus")
    #expect(journey.calls[0].expectedArrival == nil)
    #expect(journey.calls[2].expectedArrival == Date(timeIntervalSince1970: 100))
    #expect(journey.calls[0].name == "Stop A")
}

@Test func journeyAtStopIsFullProgress() {
    let journey = VehicleJourney(vehicle: bus(next: "A", onward: ["B"], atStop: true, percentage: 10), direction: nil)
    #expect(journey.calls.map(\.state) == [.current(progress: 1), .upcoming])
}

@Test func journeyWithoutMatchStartsAtNextStop() {
    let journey = VehicleJourney(
        vehicle: bus(next: "X", onward: ["Y", "Z"]),
        direction: direction(0, ["A", "B", "C"]),
        stops: ["Y": stop("Y", lat: 1, lon: 1)]
    )
    #expect(journey.calls.map(\.stopID) == ["X", "Y", "Z"])
    #expect(journey.nextStopIndex == 0)
    #expect(journey.calls[0].name == "SIRI X")
    #expect(journey.calls[1].name == "Stop Y")
    #expect(journey.calls[1].coordinate == Foli.Coordinate(latitude: 1, longitude: 1))
    #expect(journey.calls[0].state == .current(progress: 0))
}

@Test func journeyEstimatedArrivalFallsBackToAimedPlusDelay() {
    let call = VehicleJourney.Call(
        id: 0, stopID: "A", name: "A", coordinate: nil,
        expectedArrival: nil, aimedArrival: Date(timeIntervalSince1970: 100), state: .upcoming
    )
    #expect(call.estimatedArrival(delay: 60) == Date(timeIntervalSince1970: 160))
}

@Test func journeyAlignsLoopAtTheOccurrenceFollowedByOnwardStops() {
    let journey = VehicleJourney(vehicle: bus(next: "A", onward: ["C"]), direction: direction(0, ["A", "B", "A", "C"]))
    #expect(journey.calls.map(\.stopID) == ["A", "B", "A", "C"])
    #expect(journey.nextStopIndex == 2)
}

@Test func journeyEmptyFeedHasNoCalls() {
    let journey = VehicleJourney(vehicle: bus(), direction: direction(0, ["A"]))
    #expect(journey.calls.isEmpty)
    #expect(journey.nextStopIndex == nil)
}

@Test func directionMatchingIgnoresDirectionRef() {
    let outbound = direction(0, ["A", "B", "C", "D"])
    let inbound = direction(1, ["D", "C", "B", "A"])
    #expect([outbound, inbound].bestMatch(for: bus(next: "C", onward: ["B", "A"]))?.id == 1)
    #expect([outbound, inbound].bestMatch(for: bus(next: "B", onward: ["C", "D"]))?.id == 0)
    #expect([outbound, inbound].bestMatch(for: bus(next: "Q", onward: ["R"])) == nil)
}

@Test func directionMatchingToleratesAFewVariantStops() {
    let full = direction(0, (1...10).map(String.init))
    // One of the five upcoming stops is missing from the representative trip.
    #expect([full].bestMatch(for: bus(next: "6", onward: ["7", "X", "9", "10"]))?.id == 0)
    #expect([full].bestMatch(for: bus(next: "6", onward: ["X", "Y", "9", "10"])) == nil)
}

// MARK: - Path

@Test func journeyPathFallsBackToCallCoordinates() {
    let journey = VehicleJourney(vehicle: bus(next: "B", onward: ["C"]), direction: direction(0, ["A", "B", "C"]))
    #expect(journey.path == [0, 1, 2].map { Foli.Coordinate(latitude: 0, longitude: Double($0)) })
    let split = journey.splitPath(at: Foli.Coordinate(latitude: 0.1, longitude: 0.5))
    #expect(split.travelled == [Foli.Coordinate(latitude: 0, longitude: 0), Foli.Coordinate(latitude: 0, longitude: 0.5)])
    #expect(split.remaining.first == Foli.Coordinate(latitude: 0, longitude: 0.5))
    #expect(split.remaining.last == Foli.Coordinate(latitude: 0, longitude: 2))
}

@Test func journeyPathUsesShapeWhenMatched() {
    let shape = [Foli.Coordinate(latitude: 5, longitude: 5), Foli.Coordinate(latitude: 6, longitude: 6)]
    let journey = VehicleJourney(vehicle: bus(next: "B", onward: ["C"]), direction: direction(0, ["A", "B", "C"], path: shape))
    #expect(journey.path == shape)
}

@Test func splitProjectsOntoNearestSegment() {
    let line = [(0.0, 0.0), (0.0, 2.0), (2.0, 2.0)].map { Foli.Coordinate(latitude: $0, longitude: $1) }
    let split = line.split(at: Foli.Coordinate(latitude: 1, longitude: 2.1))
    #expect(split.travelled == [line[0], line[1], Foli.Coordinate(latitude: 1, longitude: 2)])
    #expect(split.remaining == [Foli.Coordinate(latitude: 1, longitude: 2), line[2]])
}

@Test func splitSearchStartSkipsEarlierPassOfALoop() {
    // Out along latitude 0 and back along latitude 0.001.
    let loop = [(0.0, 0.0), (0.0, 1.0), (0.001, 1.0), (0.001, 0.0)].map { Foli.Coordinate(latitude: $0, longitude: $1) }
    let bus = Foli.Coordinate(latitude: 0.0004, longitude: 0.5)
    #expect(loop.split(at: bus).travelled.count == 2)
    #expect(loop.split(at: bus, searchingFrom: 2).travelled.count == 4)
}

@Test func splitOfDegenerateLines() {
    let point = Foli.Coordinate(latitude: 1, longitude: 1)
    #expect([Foli.Coordinate]().split(at: point).remaining.isEmpty)
    #expect([point].split(at: point) == (travelled: [], remaining: [point]))
}

// MARK: - ETA

@Test func etaDisplayThresholds() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ETADisplay(arrival: now.addingTimeInterval(-30), now: now) == .now)
    #expect(ETADisplay(arrival: now.addingTimeInterval(59), now: now) == .now)
    #expect(ETADisplay(arrival: now.addingTimeInterval(330), now: now) == .minutes(5))
    #expect(ETADisplay(arrival: now.addingTimeInterval(899), now: now) == .minutes(14))
    let far = now.addingTimeInterval(900)
    #expect(ETADisplay(arrival: far, now: now) == .clock(far))
}

// MARK: - Arrival matching

@Test func arrivalMatchesLiveRunByLineAndOrigin() {
    let arrival = Foli.Arrival(
        recordedAtTime: 0, lineRef: "15", monitored: true, originAimedDepartureTime: 1000,
        destinationAimedArrivalTime: 0, destinationDisplay: "", aimedArrivalTime: 0,
        expectedArrivalTime: 0, aimedDepartureTime: 0, expectedDepartureTime: 0
    )
    let vehicles = [bus("a", line: "15", origin: 900), bus("b", line: "7", origin: 1000), bus("c", line: "15", origin: 1000)]
    #expect(vehicles.trip(for: arrival) == TripKey(vehicleRef: "c", lineRef: "15", originAimedDepartureTime: 1000))
    #expect(vehicles.prefix(2).trip(for: arrival) == nil)
}

@Test func arrivalPrefersItsVehicleRefWhenTheRunAgrees() {
    func arrival(vehicleRef: String?) -> Foli.Arrival {
        Foli.Arrival(
            recordedAtTime: 0, lineRef: "15", monitored: true, originAimedDepartureTime: 1000,
            destinationAimedArrivalTime: 0, destinationDisplay: "", aimedArrivalTime: 0,
            expectedArrivalTime: 0, aimedDepartureTime: 0, expectedDepartureTime: 0,
            vehicleRef: vehicleRef
        )
    }
    // Two buses report the same run (e.g. a swap); the arrival names the one serving it.
    let vehicles = [bus("a", line: "15", origin: 1000), bus("b", line: "15", origin: 1000), bus("c", line: "15", origin: 900)]
    #expect(vehicles.trip(for: arrival(vehicleRef: "b"))?.vehicleRef == "b")
    // A ref now on another run falls back to line and origin.
    #expect(vehicles.trip(for: arrival(vehicleRef: "c"))?.vehicleRef == "a")
}

// MARK: - Tracker

private let t0 = Date(timeIntervalSince1970: 0)
private let key = TripKey(vehicleRef: "v1", lineRef: "15", originAimedDepartureTime: 1000)

@Test func tripStatusIsPendingUntilSeenThenLive() {
    var tracker = VehicleTracker(scope: .trip(key), interval: 5)
    #expect(tracker.tripStatus(at: t0).map { if case .pending = $0 { true } else { false } } == true)
    tracker.update(with: [bus(next: "A", onward: ["B"]), bus("v2")], at: t0)
    guard case .live(let position) = tracker.tripStatus(at: t0) else { Issue.record("not live"); return }
    #expect(position.id == "v1")
    #expect(tracker.positions(at: t0).map(\.id) == ["v1"])
    #expect(VehicleTracker(scope: .line("15"), interval: 5).tripStatus(at: t0) == nil)
}

@Test func trackerHoldsMissingVehicleForGraceThenLoses() {
    var tracker = VehicleTracker(scope: .trip(key), interval: 5, grace: 60)
    tracker.update(with: [bus(next: "A", onward: ["B"], lat: 1, lon: 1)], at: t0)
    tracker.update(with: [], at: t0.addingTimeInterval(30))
    guard case .stale(let position, let lastSeen) = tracker.tripStatus(at: t0.addingTimeInterval(30)) else {
        Issue.record("not stale"); return
    }
    #expect(lastSeen == t0)
    #expect(position.coordinate == Foli.Coordinate(latitude: 1, longitude: 1))
    tracker.update(with: [], at: t0.addingTimeInterval(61))
    #expect(tracker.tripStatus(at: t0.addingTimeInterval(61)).map { if case .lost = $0 { true } else { false } } == true)
    #expect(tracker.positions(at: t0.addingTimeInterval(61)).isEmpty)
}

@Test func trackerEndsTripOnNewRun() {
    var tracker = VehicleTracker(scope: .trip(key), interval: 5)
    tracker.update(with: [bus(next: "A", onward: ["B"])], at: t0)
    tracker.update(with: [bus(origin: 5000, next: "A", onward: ["B"])], at: t0.addingTimeInterval(5))
    #expect(tracker.tripStatus(at: t0).map { if case .ended = $0 { true } else { false } } == true)
    #expect(tracker.positions(at: t0).isEmpty)
    // Stays ended even if the old run seems to reappear.
    tracker.update(with: [bus(next: "A", onward: ["B"])], at: t0.addingTimeInterval(10))
    #expect(tracker.tripStatus(at: t0).map { if case .ended = $0 { true } else { false } } == true)
}

@Test func trackerEndsTripWhenBusVanishesAtTerminus() {
    var tracker = VehicleTracker(scope: .trip(key), interval: 5)
    tracker.update(with: [bus(next: "Z", onward: [], atStop: true)], at: t0)
    tracker.update(with: [], at: t0.addingTimeInterval(5))
    #expect(tracker.tripStatus(at: t0).map { if case .ended = $0 { true } else { false } } == true)
}

@Test func trackerTripKeyWithoutOriginMatchesOnLine() {
    var tracker = VehicleTracker(scope: .trip(TripKey(vehicleRef: "v1", lineRef: "15", originAimedDepartureTime: nil)), interval: 5)
    tracker.update(with: [bus(origin: 1234, next: "A", onward: ["B"])], at: t0)
    #expect(tracker.tripStatus(at: t0).map { if case .live = $0 { true } else { false } } == true)
    tracker.update(with: [bus(line: "7", next: "A", onward: ["B"])], at: t0)
    #expect(tracker.tripStatus(at: t0).map { if case .ended = $0 { true } else { false } } == true)
}

@Test func lineScopeDropsLeaversAtOnceButHoldsDropouts() {
    var tracker = VehicleTracker(scope: .line("15"), interval: 5, grace: 60)
    tracker.update(with: [bus("a", next: "A", onward: ["B"]), bus("b", next: "A", onward: ["B"])], at: t0)
    // "a" is still in the feed but on another line; "b" dropped out of the feed.
    tracker.update(with: [bus("a", line: "7", next: "A", onward: ["B"])], at: t0.addingTimeInterval(5))
    #expect(tracker.positions(at: t0).map(\.id) == ["b"])
    tracker.update(with: [], at: t0.addingTimeInterval(61))
    #expect(tracker.positions(at: t0).isEmpty)
}
