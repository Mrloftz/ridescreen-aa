// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class TripRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var statusMessage = "Ready to record."
    @Published private(set) var speedKmh = 0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var movingTime: TimeInterval = 0
    @Published private(set) var maxSpeedMetersPerSecond = 0.0
    @Published private(set) var accuracyMeters: Double?

    let store: TripStore

    private let manager: CLLocationManager
    private var draft: RideDraft?
    private var lastLocation: CLLocation?
    private var lastCheckpointAt: Date?
    private var startPendingAuthorization = false

    init(store: TripStore = TripStore()) {
        self.store = store
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = true
    }

    var needsLocationSettings: Bool {
        !CLLocationManager.locationServicesEnabled()
            || authorizationStatus == .denied
            || authorizationStatus == .restricted
    }

    func startRecording() {
        guard !isRecording else { return }
        guard store.canRecord else {
            statusMessage = store.errorMessage ?? "Ride history is unavailable."
            return
        }

        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            startPendingAuthorization = true
            statusMessage = "Allow location access to start recording."
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginRecording()
        case .denied, .restricted:
            statusMessage = "Enable location access for RideScreen in iOS Settings."
        @unknown default:
            statusMessage = "Location access is unavailable on this device."
        }
    }

    func stopRecording() {
        guard isRecording, let draft else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRecording = false
        startPendingAuthorization = false

        if store.finish(draft) {
            self.draft = nil
            lastLocation = nil
            lastCheckpointAt = nil
            statusMessage = TripRules.isMeaningful(draft)
                ? "Ride saved on this iPhone."
                : "Ride was too short to save."
        } else {
            statusMessage = store.errorMessage ?? "Ride history could not be saved."
        }
        speedKmh = 0
        accuracyMeters = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard startPendingAuthorization else { return }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startPendingAuthorization = false
            beginRecording()
        case .denied, .restricted:
            startPendingAuthorization = false
            statusMessage = "Enable location access for RideScreen in iOS Settings."
        case .notDetermined:
            break
        @unknown default:
            startPendingAuthorization = false
            statusMessage = "Location access is unavailable on this device."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording else { return }
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            record(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isRecording else { return }
        if let locationError = error as? CLError, locationError.code == .denied {
            stopRecording()
            statusMessage = store.errorMessage
                ?? "Location access stopped. The ride was saved if it met the minimum length."
        } else {
            statusMessage = "Waiting for a reliable GPS signal."
        }
    }

    private func beginRecording() {
        guard store.canRecord else {
            statusMessage = store.errorMessage ?? "Ride history is unavailable."
            return
        }

        let newDraft = RideDraft()
        guard store.checkpoint(newDraft) else {
            statusMessage = store.errorMessage ?? "Ride history could not be saved."
            return
        }

        draft = newDraft
        lastLocation = nil
        lastCheckpointAt = .now
        distanceMeters = 0
        movingTime = 0
        maxSpeedMetersPerSecond = 0
        speedKmh = 0
        accuracyMeters = nil
        manager.allowsBackgroundLocationUpdates = true
        isRecording = true
        statusMessage = "Recording. Location stays active while this ride is in progress."
        manager.startUpdatingLocation()
    }

    private func record(_ location: CLLocation) {
        guard var currentDraft = draft else { return }
        let timestamp = location.timestamp
        guard abs(timestamp.timeIntervalSinceNow) <= 15,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= TripRules.maximumAccuracyMeters else {
            return
        }

        let previous = lastLocation
        let elapsed = previous.map { timestamp.timeIntervalSince($0.timestamp) } ?? 0
        let distance = previous.map { location.distance(from: $0) } ?? 0
        if elapsed > 0, distance / elapsed > TripRules.maximumPlausibleSpeedMetersPerSecond {
            return
        }

        let reportedSpeed = location.speed
        let speed = reportedSpeed >= 0 && reportedSpeed.isFinite
            ? reportedSpeed
            : (elapsed > 0 ? distance / elapsed : 0)
        let isMoving = speed >= TripRules.movingSpeedMetersPerSecond
        let isBridgedGap = elapsed > 5
            && elapsed <= TripRules.maximumGapBridge
            && distance / elapsed >= TripRules.movingSpeedMetersPerSecond

        if !isMoving, !isBridgedGap,
           let lastMovingAt = currentDraft.lastMovingAt,
           timestamp.timeIntervalSince(lastMovingAt) >= TripRules.idleSplitAfter,
           currentDraft.distanceMeters > 0 {
            guard store.finish(currentDraft, at: lastMovingAt) else {
                statusMessage = store.errorMessage ?? "Ride history could not be saved."
                return
            }
            currentDraft = RideDraft(startedAt: timestamp)
            guard store.checkpoint(currentDraft) else {
                draft = nil
                isRecording = false
                manager.stopUpdatingLocation()
                manager.allowsBackgroundLocationUpdates = false
                statusMessage = store.errorMessage ?? "Ride history could not be saved."
                return
            }
            distanceMeters = 0
            movingTime = 0
            maxSpeedMetersPerSecond = 0
            lastLocation = nil
        }

        if let previous = lastLocation {
            let interval = timestamp.timeIntervalSince(previous.timestamp)
            if isMoving, interval > 0, interval <= 5 {
                currentDraft.distanceMeters += distance
                currentDraft.movingTime += interval
            } else if isBridgedGap {
                currentDraft.distanceMeters += distance
                currentDraft.movingTime += interval
            }
        }

        if isMoving || isBridgedGap {
            currentDraft.lastMovingAt = timestamp
        }
        currentDraft.maxSpeedMetersPerSecond = max(currentDraft.maxSpeedMetersPerSecond, speed)
        currentDraft.updatedAt = timestamp
        currentDraft.points.append(
            TrackPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: timestamp,
                speedMetersPerSecond: speed
            )
        )

        draft = currentDraft
        lastLocation = location
        distanceMeters = currentDraft.distanceMeters
        movingTime = currentDraft.movingTime
        maxSpeedMetersPerSecond = currentDraft.maxSpeedMetersPerSecond
        speedKmh = max(0, Int((speed * 3.6).rounded()))
        accuracyMeters = location.horizontalAccuracy
        if statusMessage == "Waiting for a reliable GPS signal." {
            statusMessage = "Recording. Location stays active while this ride is in progress."
        }

        if let lastCheckpointAt,
           timestamp.timeIntervalSince(lastCheckpointAt) >= TripRules.checkpointInterval {
            if store.checkpoint(currentDraft) {
                self.lastCheckpointAt = timestamp
            } else {
                statusMessage = store.errorMessage ?? "Ride history could not be saved."
            }
        }
    }
}
