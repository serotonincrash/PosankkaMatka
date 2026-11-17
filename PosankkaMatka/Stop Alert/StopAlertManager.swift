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

/// The one active "Alert Me Here": a geofence on the rider's own location
/// around the stop, plus a countdown Live Activity. Either ending ends both;
/// setting a new alert replaces the old.
///
/// Call `resume()` at launch: a geofence hit can relaunch the app in the
/// background, and only a live `CLMonitor` with the same name receives it.
@MainActor
@Observable
final class StopAlertManager {
    /// What's persisted across launches.
    struct ActiveAlert: Codable, Equatable {
        let attributes: StopAlertAttributes
        let latitude: Double
        let longitude: Double
        var state: StopAlertAttributes.ContentState
    }

    private(set) var active: ActiveAlert?

    /// Whether the geofence can fire with the app closed. False after the
    /// rider declined Always; the alert then only works while the app runs.
    var canAlertInBackground: Bool { locationManager.authorizationStatus == .authorizedAlways }
    var isLocationDenied: Bool {
        [.denied, .restricted].contains(locationManager.authorizationStatus)
    }

    private static let radius: CLLocationDistance = 350
    private static let monitorName = "StopAlert"
    private static let conditionID = "stop"
    private static let notificationID = "stopAlert"
    private static let defaultsKey = "StopAlertManager.active"
    /// A resumed alert this far past its ETA is abandoned.
    private static let expiry: TimeInterval = 30 * 60

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let notificationPresenter = NotificationPresenter()
    @ObservationIgnored private var monitor: CLMonitor?
    /// Holding this keeps the Always authorization goal (and the prompt) alive.
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var activityTask: Task<Void, Never>?

    init() {
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    func isAlerting(stopID: String, trip: TripKey) -> Bool {
        guard let attributes = active?.attributes else { return false }
        return attributes.stopID == stopID && attributes.vehicleRef == trip.vehicleRef
            && attributes.originAimedDepartureTime == trip.originAimedDepartureTime
    }

    // MARK: - Lifecycle

    /// Starts an alert, replacing any active one. First use prompts for
    /// notifications and Always location.
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
            state: state
        )
        active = alert
        persist()

        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        session = CLServiceSession(authorization: .always)
        await startMonitoring(alert, fresh: true)
        startActivity(alert)
    }

    /// Feeds the latest estimate; call on each foreground poll.
    func update(eta: Date, nextStopName: String?, delaySeconds: Int?, at now: Date = .now) async {
        guard var alert = active, !alert.state.hasArrived else { return }
        alert.state.eta = eta
        alert.state.updatedAt = now
        alert.state.nextStopName = nextStopName
        alert.state.delaySeconds = delaySeconds
        active = alert
        persist()
        for activity in Activity<StopAlertAttributes>.activities {
            await activity.update(ActivityContent(state: alert.state, staleDate: alert.state.staleDate))
        }
    }

    /// Ends the alert, its geofence and its Live Activity.
    func cancel() async {
        await tearDown()
    }

    /// Reattaches to a persisted alert after launch, or cleans up leftovers.
    func resume(now: Date = .now) async {
        guard let alert = loadPersisted(),
              now.timeIntervalSince(alert.state.eta) < Self.expiry else {
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
        session = CLServiceSession(authorization: .always)
        await startMonitoring(alert, fresh: false)
        if let activity { observe(activity) }
    }

    // MARK: - Geofence

    private func startMonitoring(_ alert: ActiveAlert, fresh: Bool) async {
        let monitor = await monitor()
        let existing = await monitor.record(for: Self.conditionID)
        if fresh || existing == nil {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: alert.latitude, longitude: alert.longitude),
                radius: Self.radius
            )
            // Already inside counts as arriving.
            await monitor.add(condition, identifier: Self.conditionID, assuming: .unsatisfied)
        }
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            do {
                for try await event in await monitor.events
                where event.identifier == Self.conditionID && event.state == .satisfied {
                    await self?.arrive()
                    return
                }
            } catch {}
        }
    }

    /// One monitor per name may exist, so it's created once and reused.
    private func monitor() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor(Self.monitorName)
        monitor = created
        return created
    }

    private func arrive() async {
        guard var alert = active else { return }
        alert.state.hasArrived = true
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Approaching \(alert.attributes.stopName)")
        content.body = String(localized: "Your stop on line \(alert.attributes.lineName) is coming up.")
        content.sound = .default
        // Needs the Time Sensitive Notifications capability; otherwise plain.
        content.interruptionLevel = .timeSensitive
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
        )
        await tearDown(finalState: alert.state)
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
            observe(activity)
        } catch {
            // The geofence still works without the countdown.
        }
    }

    /// The rider dismissing the activity cancels the geofence too.
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

    /// `finalState` leaves the ended activity on screen briefly showing it.
    private func tearDown(finalState: StopAlertAttributes.ContentState? = nil) async {
        // Cancel observers first so ending the activity doesn't re-enter.
        activityTask?.cancel()
        activityTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        active = nil
        persist()

        if let monitor { await monitor.remove(Self.conditionID) }
        session?.invalidate()
        session = nil

        for activity in Activity<StopAlertAttributes>.activities {
            if let finalState {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(.now.addingTimeInterval(5 * 60))
                )
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
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
