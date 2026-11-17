import Testing
import FoliBusAPI
@testable import PosankkaCore

private let route15 = Foli.Route(id: "r15", shortName: "15", longName: "", type: 3, colorHex: nil, textColorHex: nil)
private let route7 = Foli.Route(id: "r7", shortName: "7", longName: "", type: 3, colorHex: nil, textColorHex: nil)
private let stopA = Foli.Stop(id: "A", name: "A")
private let stopB = Foli.Stop(id: "B", name: "B")
private let bus1 = TripKey(vehicleRef: "1", lineRef: "15", originAimedDepartureTime: 100)
private let bus2 = TripKey(vehicleRef: "2", lineRef: "15", originAimedDepartureTime: 200)

@Test func routeFromListsStartsFreshStack() {
    var selection = Selection([.route(route7), .stop(stopA), .vehicle(bus1)])
    selection.openRoute(route15)
    #expect(selection.cards == [.route(route15)])
    #expect(selection.route == route15)
}

@Test func stopFromRouteListPushesAndPopReturnsToRoute() {
    var selection = Selection()
    selection.openRoute(route15)
    selection.push(.stop(stopA))
    #expect(selection.stop == stopA)
    #expect(selection.route == route15)  // still drawn under the stop
    selection.pop()
    #expect(selection.top == .route(route15))
    #expect(selection.stop == nil)
}

@Test func pushingTheTopCardAgainIsNoOp() {
    var selection = Selection([.stop(stopA)])
    selection.push(.stop(stopA))
    #expect(selection.cards.count == 1)
}

@Test func mapTapsSwapSameKindTopButPushOverOtherKinds() {
    var selection = Selection([.route(route15), .stop(stopA)])
    selection.pushReplacingSameKind(.stop(stopB))
    #expect(selection.cards == [.route(route15), .stop(stopB)])

    selection.pushReplacingSameKind(.vehicle(bus1))
    selection.pushReplacingSameKind(.vehicle(bus2))
    #expect(selection.cards == [.route(route15), .stop(stopB), .vehicle(bus2)])
    #expect(selection.vehicle == bus2)
    #expect(selection.stop == nil)
}

@Test func unboundedStackPopsOneAndPopAllEmpties() {
    var selection = Selection([.route(route15)])
    selection.push(.vehicle(bus1))
    selection.push(.stop(stopA))
    selection.push(.vehicle(bus2))
    selection.push(.stop(stopB))
    #expect(selection.cards.count == 5)
    selection.pop()
    #expect(selection.vehicle == bus2)
    selection.popAll()
    #expect(selection.isEmpty)
    selection.pop()  // popping empty is harmless
    #expect(selection.isEmpty)
}
