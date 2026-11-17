import Foundation
import Testing
import FoliBusAPI
@testable import PosankkaCore

private func route(_ shortName: String) -> Foli.Route {
    Foli.Route(id: shortName, shortName: shortName, longName: "Line \(shortName)", type: 3, colorHex: nil, textColorHex: nil)
}

private func vehicle(_ ref: String, line: String, lat: Double, lon: Double) -> Foli.VehicleLocation {
    Foli.VehicleLocation(
        recordedAtTime: 0, validUntilTime: 0, lineRef: line, directionRef: "1",
        publishedLineName: line, operatorRef: "x", monitored: true, inCongestion: false,
        inPanic: false, longitude: lon, latitude: lat, vehicleRef: ref
    )
}

@Test func routesSortByLeadingNumberThenNonNumeric() {
    let sorted = [route("Lautta"), route("15"), route("2A"), route("2")].sortedByLine()
    #expect(sorted.map(\.shortName) == ["2", "2A", "15", "Lautta"])
}

@Test func nearestSortsCapsAndSkipsPositionless() {
    let origin = Foli.Coordinate(latitude: 60.45, longitude: 22.27)
    let stops = [
        Foli.Stop(id: "far", name: "Far", latitude: 60.46, longitude: 22.27),   // ~1.1 km
        Foli.Stop(id: "near", name: "Near", latitude: 60.451, longitude: 22.27), // ~110 m
        Foli.Stop(id: "none", name: "None"),
    ]
    #expect(stops.nearest(to: origin).map(\.stop.id) == ["near", "far"])
    #expect(stops.nearest(to: origin, withinMeters: 500).map(\.stop.id) == ["near"])
    #expect(abs(stops.nearest(to: origin)[0].distance - 111) < 2)
}

@Test func trackerInterpolatesAndFiltersByScope() {
    var tracker = VehicleTracker(scope: .line("15"), interval: 10)
    let t0 = Date(timeIntervalSince1970: 0)
    tracker.update(with: [vehicle("a", line: "15", lat: 0, lon: 0), vehicle("b", line: "7", lat: 0, lon: 0)], at: t0)
    tracker.update(with: [vehicle("a", line: "15", lat: 1, lon: 2)], at: t0)

    #expect(tracker.positions(at: t0).map(\.id) == ["a"])
    let mid = tracker.positions(at: t0.addingTimeInterval(5))[0].coordinate
    #expect(mid == Foli.Coordinate(latitude: 0.5, longitude: 1))
    let late = tracker.positions(at: t0.addingTimeInterval(60))[0].coordinate
    #expect(late == Foli.Coordinate(latitude: 1, longitude: 2))
}
