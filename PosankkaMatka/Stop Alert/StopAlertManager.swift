//
//  StopAlertManager.swift
//  PosankkaMatka
//

import ActivityKit
import CoreLocation
import Foundation
import Observation
import UserNotifications
import FoliBusUI
import PosankkaCore

/// The one active "Alert Me Here": a background location session that shows
/// the rider's distance to the stop and whether the bus is about to reach it.
/// It polls the stop's small arrivals feed, notifies per `StopAlertPolicy`,
/// and drives a Live Activity. Setting a new alert replaces the old.
///
/// Needs only When-In-Use: the session starts in the foreground and keeps
/// running in the background (location background mode, blue indicator).
@MainActor
@Observable
final class StopAlertManager {
    /// What's persisted across launches.
    struct ActiveAlert: Codable, Equatable {
        let attributes: StopAlertAttributes
        let latitude: Double
        let longitude: Double
        var state: StopAlertAttributes.ContentState
        var sessionStart: Date
        var sent: Set<StopAlertPolicy.Alert> = []
    }

    private(set) var active: ActiveAlert?

    private static let pollInterval: Duration = .seconds(30)
    /// A fix older than this says nothing about where the rider is now.
    private static let fixMaxAge: TimeInterval = 120
    /// Consecutive misses before the trip counts as gone from the stop feed.
    private static let missesToConfirm = 2
    /// Whatever is due this soon after setting the alert is on the rider's
    /// screen already; it's marked sent without a notification.
    private static let setupGrace: TimeInterval = 15
    private static let geofenceRadius: CLLocationDistance = 350
    private static let monitorName = "StopAlert"
    private static let conditionID = "stop"
    private static let defaultsKey = "StopAlertManager.active"

    @ObservationIgnored private let client: FoliClient
    @ObservationIgnored private let notificationPresenter = NotificationPresenter()
    @ObservationIgnored private var feed: LocationFeed?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    @ObservationIgnored private var lastFix: CLLocation?
    @ObservationIgnored private var seenInFeed = false
    @ObservationIgnored private var feedMisses = 0
    @ObservationIgnored private var lastPushed: (state: StopAlertAttributes.ContentState, at: Date)?

    init(client: FoliClient) {
        self.client = client
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    func isAlerting(stopID: String, trip: TripKey) -> Bool {
        guard let attributes = active?.attributes else { return false }
        return attributes.stopID == stopID && attributes.trip == trip
    }

    // MARK: - Lifecycle

    /// Starts an alert, replacing any active one. Must run in the foreground:
    /// that's when a When-In-Use session may begin.
    func setAlert(
        _ attributes: StopAlertAttributes,
        at coordinate: CLLocationCoordinate2D,
        state: StopAlertAttributes.ContentState
    ) async {
        await tearDown()
        let alert = ActiveAlert(
            attributes: attributes,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            state: state,
            sessionStart: .now
        )
        active = alert
        persist()

        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        await startSession(alert, freshGeofence: true)
        startActivity(alert)
    }

    /// Feeds the vehicle card's estimate while it's on screen; fresher than
    /// the 30 s stop-feed poll.
    func update(eta: Date, nextStopName: String?, at now: Date = .now) async {
        guard var alert = active, !alert.state.hasArrived else { return }
        alert.state.eta = eta
        alert.state.updatedAt = now
        alert.state.nextStopName = nextStopName
        active = alert
        await evaluate()
    }

    /// Ends the session, geofence and Live Activity.
    func cancel() async {
        await tearDown()
    }

    /// Reattaches to a persisted session after a relaunch, or cleans up.
    func resume(now: Date = .now) async {
        guard let alert = loadPersisted(),
              now.timeIntervalSince(alert.sessionStart) < StopAlertPolicy.maxDuration else {
            await tearDown()
            return
        }
        let activity = Activity<StopAlertAttributes>.activities.first
        // Dismissed from the lock screen while the app wasn't running.
        if activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled {
            await tearDown()
            return
        }
        active = alert
        // A relaunched app must recreate its background session promptly.
        await startSession(alert, freshGeofence: false)
        if let activity { observe(activity) }
    }

    // MARK: - Session

    private func startSession(_ alert: ActiveAlert, freshGeofence: Bool) async {
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        let feed = LocationFeed { [weak self] location in
            self?.lastFix = location
            Task { await self?.evaluate() }
        }
        self.feed = feed
        feed.start()
        seenInFeed = false
        feedMisses = 0
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        await startGeofence(alert, fresh: freshGeofence)
    }

    /// The stop's own feed (~10 KB), not the whole-network vehicle feed.
    private func poll() async {
        guard let stopID = active?.attributes.stopID else { return }
        guard let arrivals = try? await client.fetchArrivals(for: stopID),
              var alert = active, alert.attributes.stopID == stopID else { return }
        if let arrival = arrivals.arrival(for: alert.attributes.trip) {
            seenInFeed = true
            feedMisses = 0
            alert.state.eta = arrival.expectedArrivalDate
            alert.state.updatedAt = .now
            active = alert
        } else if seenInFeed {
            feedMisses += 1
        }
        await evaluate()
    }

    private func evaluate(now: Date = .now) async {
        guard var alert = active else { return }
        let fix = lastFix.flatMap { now.timeIntervalSince($0.timestamp) < Self.fixMaxAge ? $0 : nil }
        let distance = fix?.distance(from: CLLocation(latitude: alert.latitude, longitude: alert.longitude))
        alert.state.distanceMeters = distance
        alert.state.walkingMinutes = distance.map {
            Int((StopAlertPolicy.walkingTime(forDistance: $0) / 60).rounded(.up))
        }
        let outcome = StopAlertPolicy.evaluate(.init(
            now: now,
            sessionStart: alert.sessionStart,
            busETA: alert.state.eta,
            busMissingFromFeed: feedMisses >= Self.missesToConfirm,
            distance: distance,
            speed: fix.flatMap { $0.speed >= 0 ? $0.speed : nil },
            sent: alert.sent
        ))
        var notice: UNNotificationContent?
        if let kind = outcome.notify {
            alert.sent.insert(kind)
            if now.timeIntervalSince(alert.sessionStart) >= Self.setupGrace {
                notice = await notify(kind, alert: alert)
            }
        }
        active = alert
        persist()
        if let end = outcome.end {
            alert.state.hasArrived = end == .arrived
            alert.state.busPassed = end == .busPassed
            await tearDown(finalState: alert.state, lingering: end == .arrived ? 5 * 60 : 60)
        } else {
            await pushActivity(alert.state, now: now, alerting: notice)
        }
    }

    /// Posts the notification and returns it, so the Live Activity can pop too.
    private func notify(_ kind: StopAlertPolicy.Alert, alert: ActiveAlert) async -> UNNotificationContent {
        let line = alert.attributes.lineName
        let stop = alert.attributes.stopName
        let minutes = max(0, Int((alert.state.eta.timeIntervalSinceNow / 60).rounded()))
        let title: String
        let body: String
        switch kind {
        case .leaveNow:
            title = String(localized: "Leave now for \(stop)")
            if let walk = alert.state.walkingMinutes {
                body = String(localized: "Bus \(line) arrives in \(minutes) min; it's about a \(walk) min walk.")
            } else {
                body = String(localized: "Bus \(line) arrives in \(minutes) min.")
            }
        case .busArriving:
            title = String(localized: "Bus \(line) is arriving")
            body = String(localized: "At \(stop) in about \(minutes) min.")
        case .stopIsNext:
            title = String(localized: "Your stop is next")
            body = String(localized: "\(stop) is coming up on bus \(line).")
        }
        return await post(id: "stopAlert.\(kind.rawValue)", title: title, body: body)
    }

    @discardableResult
    private func post(id: String, title: String, body: String) async -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Needs the Time Sensitive Notifications capability; otherwise plain.
        content.interruptionLevel = .timeSensitive
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
        return content
    }

    // MARK: - Geofence fallback

    /// Only fires with the session dead (force-quit relaunch, which needs
    /// Always, granted elsewhere or not at all); a live session decides itself.
    private func startGeofence(_ alert: ActiveAlert, fresh: Bool) async {
        let monitor = await monitor()
        let existing = await monitor.record(for: Self.conditionID)
        if fresh || existing == nil {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: alert.latitude, longitude: alert.longitude),
                radius: Self.geofenceRadius
            )
            await monitor.add(condition, identifier: Self.conditionID, assuming: .unsatisfied)
        }
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            do {
                for try await event in await monitor.events
                where event.identifier == Self.conditionID && event.state == .satisfied {
                    await self?.geofenceEntered()
                }
            } catch {}
        }
    }

    private func geofenceEntered() async {
        guard var alert = active, !alert.sent.contains(.stopIsNext) else { return }
        if let lastFix, Date().timeIntervalSince(lastFix.timestamp) < Self.fixMaxAge { return }
        alert.sent.insert(.stopIsNext)
        active = alert
        persist()
        await post(
            id: "stopAlert.geofence",
            title: String(localized: "Approaching \(alert.attributes.stopName)"),
            body: String(localized: "You're near your stop for bus \(alert.attributes.lineName).")
        )
    }

    /// One monitor per name may exist, so it's created once and reused.
    private func monitor() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor(Self.monitorName)
        monitor = created
        return created
    }

    // MARK: - Live Activity

    private func startActivity(_ alert: ActiveAlert) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let activity = try Activity.request(
                attributes: alert.attributes,
                content: ActivityContent(state: alert.state, staleDate: alert.state.staleDate),
                pushType: nil
            )
            lastPushed = (alert.state, .now)
            observe(activity)
        } catch {
            // Notifications still work without it.
        }
    }

    /// Skips updates that wouldn't change what's on screen, unless `alerting`
    /// asks to light up the Dynamic Island or Lock Screen.
    private func pushActivity(
        _ state: StopAlertAttributes.ContentState,
        now: Date,
        alerting notice: UNNotificationContent? = nil
    ) async {
        if notice == nil, let lastPushed, now.timeIntervalSince(lastPushed.at) < 60,
           lastPushed.state.eta == state.eta,
           lastPushed.state.walkingMinutes == state.walkingMinutes,
           lastPushed.state.nextStopName == state.nextStopName,
           Self.distanceBucket(lastPushed.state.distanceMeters) == Self.distanceBucket(state.distanceMeters) {
            return
        }
        lastPushed = (state, now)
        let alert = notice.map {
            AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: $0.title),
                body: LocalizedStringResource(stringLiteral: $0.body),
                sound: .default
            )
        }
        for activity in Activity<StopAlertAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: state.staleDate), alertConfiguration: alert)
        }
    }

    private static func distanceBucket(_ meters: Double?) -> Int? {
        meters.map { Int($0 / 50) }
    }

    /// The rider dismissing the activity ends the session too.
    private func observe(_ activity: Activity<StopAlertAttributes>) {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
                guard !Task.isCancelled else { return }
                await self?.tearDown()
                return
            }
        }
    }

    // MARK: - Teardown

    /// `finalState` leaves the ended activity on screen for `lingering` seconds.
    private func tearDown(
        finalState: StopAlertAttributes.ContentState? = nil,
        lingering: TimeInterval = 0
    ) async {
        // Cancel observers first so ending the activity doesn't re-enter.
        activityTask?.cancel()
        activityTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        pollTask?.cancel()
        pollTask = nil
        lastFix = nil
        lastPushed = nil
        active = nil
        persist()

        // Before the location session goes: in the background it's what keeps
        // the app running, and without it the end waits for the next launch.
        for activity in Activity<StopAlertAttributes>.activities {
            if let finalState {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(.now.addingTimeInterval(lingering))
                )
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        feed?.stop()
        feed = nil
        if let monitor { await monitor.remove(Self.conditionID) }
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    // MARK: - Persistence

    private func persist() {
        let defaults = UserDefaults.standard
        if let active, let data = try? JSONEncoder().encode(active) {
            defaults.set(data, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    private func loadPersisted() -> ActiveAlert? {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ActiveAlert.self, from: data)
    }
}

/// Continuous updates that don't pause while the rider stands still:
/// `CLLocationUpdate.liveUpdates` pauses (and may suspend the app) when
/// stationary, which would stop the poll while someone waits at home.
@MainActor
private final class LocationFeed: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let onUpdate: @MainActor (CLLocation) -> Void

    init(onUpdate: @escaping @MainActor (CLLocation) -> Void) {
        self.onUpdate = onUpdate
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Delegate calls arrive on the main thread, where the manager was made.
        MainActor.assumeIsolated { onUpdate(location) }
    }
}

extension StopAlertAttributes {
    /// Builds the attributes from the app's models.
    init(
        trip: TripKey,
        lineName: String,
        route: Foli.Route?,
        destinationName: String?,
        stopID: String,
        stopName: String
    ) {
        self.init(
            lineName: lineName,
            lineColorHex: route?.colorHex,
            lineTextColorHex: route?.textColorHex,
            destinationName: destinationName,
            stopID: stopID,
            stopName: stopName,
            vehicleRef: trip.vehicleRef,
            lineRef: trip.lineRef,
            originAimedDepartureTime: trip.originAimedDepartureTime
        )
    }

    var trip: TripKey {
        TripKey(vehicleRef: vehicleRef, lineRef: lineRef, originAimedDepartureTime: originAimedDepartureTime)
    }
}

/// Shows the stop alert as a banner even while the app is in the foreground.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
