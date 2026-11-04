// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct TrackPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speedMetersPerSecond: Double
}

struct RideDraft: Codable, Hashable {
    let id: UUID
    let startedAt: Date
    var updatedAt: Date
    var distanceMeters: Double
    var movingTime: TimeInterval
    var maxSpeedMetersPerSecond: Double
    var lastMovingAt: Date?
    var points: [TrackPoint]

    init(startedAt: Date = .now) {
        id = UUID()
        self.startedAt = startedAt
        updatedAt = startedAt
        distanceMeters = 0
        movingTime = 0
        maxSpeedMetersPerSecond = 0
        lastMovingAt = nil
        points = []
    }

    func completed(at endedAt: Date) -> Ride {
        Ride(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            movingTime: movingTime,
            maxSpeedMetersPerSecond: maxSpeedMetersPerSecond,
            points: points
        )
    }
}

struct Ride: Codable, Hashable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let movingTime: TimeInterval
    let maxSpeedMetersPerSecond: Double
    let points: [TrackPoint]
}

enum TripRules {
    static let maximumAccuracyMeters = 35.0
    static let maximumPlausibleSpeedMetersPerSecond = 75.0
    static let movingSpeedMetersPerSecond = 0.8
    static let minimumRideDistanceMeters = 300.0
    static let minimumRideMovingTime: TimeInterval = 30
    static let maximumGapBridge: TimeInterval = 10 * 60
    static let idleSplitAfter: TimeInterval = 3 * 60
    static let checkpointInterval: TimeInterval = 30

    static func isMeaningful(_ draft: RideDraft) -> Bool {
        draft.distanceMeters >= minimumRideDistanceMeters
            && draft.movingTime >= minimumRideMovingTime
            && draft.points.count >= 2
    }
}
