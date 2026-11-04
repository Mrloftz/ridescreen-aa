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
    @Published private(set) var needsSaveRetry = false

    let store: TripStore

    private let manager: CLLocationManager
    private var draft: RideDraft?
    private var lastLocation: CLLocation?
    private var fallbackMotionAnchor: CLLocation?
    private var lastCheckpointAt: Date?
    private var startPendingAuthorization = false
    private var awaitingFullAccuracy = false
    private var pendingSaveDraft: RideDraft?
    private var pendingSaveEndedAt: Date?

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

        if let unfinished = store.activeDraft, store.errorMessage != nil {
            pendingSaveDraft = unfinished
            pendingSaveEndedAt = unfinished.updatedAt
            needsSaveRetry = true
            statusMessage = "An unfinished ride could not be recovered. Retry saving it."
        }
    }

    var needsLocationSettings: Bool {
        !CLLocationManager.locationServicesEnabled()
            || authorizationStatus == .denied
            || authorizationStatus == .restricted
            || manager.accuracyAuthorization == .reducedAccuracy
    }

    func startRecording() {
        guard !isRecording else { return }
        guard !needsSaveRetry else {
            statusMessage = "Save the unfinished ride before starting another."
            return
        }
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
            startPendingAuthorization = true
            if manager.accuracyAuthorization == .reducedAccuracy {
                requestFullAccuracy()
            } else {
                startPendingAuthorization = false
                beginRecording()
            }
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

        let endedAt = Date.now
        if store.finish(draft, at: endedAt) {
            self.draft = nil
            lastLocation = nil
            fallbackMotionAnchor = nil
            lastCheckpointAt = nil
            statusMessage = TripRules.isMeaningful(draft)
                ? "Ride saved on this iPhone."
                : "Ride was too short to save."
        } else {
            pendingSaveDraft = draft
            pendingSaveEndedAt = endedAt
            needsSaveRetry = true
            statusMessage = store.errorMessage ?? "Ride history could not be saved."
        }
        speedKmh = 0
        accuracyMeters = nil
    }

    func retrySave() {
        guard let pendingSaveDraft else { return }
        guard store.finish(pendingSaveDraft, at: pendingSaveEndedAt ?? .now) else {
            statusMessage = store.errorMessage ?? "Ride history could not be saved."
            return
        }

        self.pendingSaveDraft = nil
        pendingSaveEndedAt = nil
        needsSaveRetry = false
        draft = nil
        lastLocation = nil
        fallbackMotionAnchor = nil
        lastCheckpointAt = nil
        statusMessage = TripRules.isMeaningful(pendingSaveDraft)
            ? "Ride saved on this iPhone."
            : "Ride was too short to save."
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if isRecording {
            let authorized = authorizationStatus == .authorizedAlways
                || authorizationStatus == .authorizedWhenInUse
            if !authorized || !CLLocationManager.locationServicesEnabled() {
                stopAfterLocationAccessLoss("Location access was turned off. Enable it in iOS Settings to continue recording.")
            } else if manager.accuracyAuthorization == .reducedAccuracy {
                stopAfterLocationAccessLoss("Precise Location was turned off. Enable it in iOS Settings to continue recording.")
            }
            return
        }

        guard startPendingAuthorization else { return }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if manager.accuracyAuthorization == .fullAccuracy {
                startPendingAuthorization = false
                awaitingFullAccuracy = false
                beginRecording()
            } else {
                requestFullAccuracy()
            }
        case .denied, .restricted:
            startPendingAuthorization = false
            awaitingFullAccuracy = false
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
        guard !isRecording else { return }
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
        fallbackMotionAnchor = nil
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

    private func stopAfterLocationAccessLoss(_ message: String) {
        stopRecording()
        if store.errorMessage == nil {
            statusMessage = message
        }
    }

    private func requestFullAccuracy() {
        guard startPendingAuthorization, !awaitingFullAccuracy else { return }
        awaitingFullAccuracy = true
        statusMessage = "Ride recording needs Precise Location to measure distance accurately."
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RideRecording") { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.awaitingFullAccuracy = false
                guard self.startPendingAuthorization else { return }
                if self.manager.accuracyAuthorization == .fullAccuracy {
                    self.startPendingAuthorization = false
                    self.beginRecording()
                } else {
                    self.startPendingAuthorization = false
                    self.statusMessage = "Turn on Precise Location for RideScreen in iOS Settings to record a route."
                }
            }
        }
    }

    private func record(_ location: CLLocation) {
        guard var currentDraft = draft else { return }
        let timestamp = location.timestamp
        guard timestamp >= currentDraft.startedAt,
              abs(timestamp.timeIntervalSinceNow) <= 15,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= TripRules.maximumAccuracyMeters else {
            return
        }

        let previous = lastLocation
        if let previous, timestamp <= previous.timestamp { return }
        let elapsed = previous.map { timestamp.timeIntervalSince($0.timestamp) } ?? 0
        let distance = previous.map { location.distance(from: $0) } ?? 0
        if elapsed > 0, distance / elapsed > TripRules.maximumPlausibleSpeedMetersPerSecond {
            return
        }

        let reportedSpeed = location.speed
        let hasReportedSpeed = reportedSpeed >= 0 && reportedSpeed.isFinite
        var speed = 0.0
        var isMoving = false
        var isBridgedGap = false
        var segmentDistance = 0.0
        var segmentMovingTime = 0.0

        if hasReportedSpeed {
            speed = reportedSpeed
            isMoving = speed >= TripRules.movingSpeedMetersPerSecond
            fallbackMotionAnchor = nil
            if previous != nil {
                if isMoving, elapsed > 0, elapsed <= 5 {
                    segmentDistance = distance
                    segmentMovingTime = elapsed
                } else if elapsed > 5,
                          elapsed <= TripRules.maximumGapBridge,
                          distance / elapsed >= TripRules.movingSpeedMetersPerSecond {
                    segmentDistance = distance
                    segmentMovingTime = elapsed
                    isBridgedGap = true
                }
            }
        } else {
            let anchor = fallbackMotionAnchor ?? previous
            if let anchor {
                let anchorInterval = timestamp.timeIntervalSince(anchor.timestamp)
                if anchorInterval > TripRules.maximumGapBridge {
                    fallbackMotionAnchor = location
                } else if anchorInterval > 0 {
                    let displacement = location.distance(from: anchor)
                    let uncertainty = max(
                        5,
                        (anchor.horizontalAccuracy + location.horizontalAccuracy) * 1.5
                    )
                    if displacement > uncertainty {
                        let estimatedSpeed = displacement / anchorInterval
                        fallbackMotionAnchor = location
                        if estimatedSpeed >= TripRules.movingSpeedMetersPerSecond,
                           estimatedSpeed <= TripRules.maximumPlausibleSpeedMetersPerSecond {
                            speed = estimatedSpeed
                            isMoving = true
                            isBridgedGap = anchorInterval > 5
                            segmentDistance = displacement
                            segmentMovingTime = anchorInterval
                        }
                    } else {
                        fallbackMotionAnchor = anchor
                    }
                } else {
                    fallbackMotionAnchor = location
                }
            } else {
                fallbackMotionAnchor = location
            }
        }

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
            fallbackMotionAnchor = nil
        }

        currentDraft.distanceMeters += segmentDistance
        currentDraft.movingTime += segmentMovingTime

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
                statusMessage = "Recording. Location stays active while this ride is in progress."
            } else {
                self.lastCheckpointAt = timestamp
                statusMessage = store.errorMessage ?? "Ride history could not be saved."
            }
        }
    }
}
