// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SwiftUI

@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var trips: [Ride] = []
    @Published private(set) var activeDraft: RideDraft?
    @Published private(set) var errorMessage: String?

    private var archive = TripArchive()
    private var canWrite = true
    private let fileURL: URL

    init() {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        fileURL = supportDirectory.appendingPathComponent("RideScreen", isDirectory: true)
            .appendingPathComponent("trips.json")
        loadArchive()
    }

    var canRecord: Bool { canWrite && archive.activeDraft == nil }

    @discardableResult
    func checkpoint(_ draft: RideDraft) -> Bool {
        if let activeDraft = archive.activeDraft, activeDraft.id != draft.id {
            errorMessage = "An unfinished ride must be recovered before starting another ride."
            return false
        }
        var candidate = archive
        candidate.activeDraft = draft
        return commit(candidate)
    }

    @discardableResult
    func finish(_ draft: RideDraft, at endedAt: Date = .now) -> Bool {
        if let activeDraft = archive.activeDraft, activeDraft.id != draft.id {
            errorMessage = "An unfinished ride must be recovered before saving another ride."
            return false
        }
        var candidate = archive
        candidate.activeDraft = nil
        if TripRules.isMeaningful(draft) {
            candidate.trips.removeAll { $0.id == draft.id }
            candidate.trips.append(draft.completed(at: endedAt))
            candidate.trips.sort { $0.startedAt > $1.startedAt }
        }
        return commit(candidate)
    }

    private func loadArchive() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            archive = try JSONDecoder().decode(TripArchive.self, from: Data(contentsOf: fileURL))
            publishArchive()

            guard let draft = archive.activeDraft else { return }
            var recovered = archive
            recovered.activeDraft = nil
            if TripRules.isMeaningful(draft) {
                recovered.trips.removeAll { $0.id == draft.id }
                recovered.trips.append(draft.completed(at: draft.updatedAt))
                recovered.trips.sort { $0.startedAt > $1.startedAt }
            }
            _ = commit(recovered)
        } catch {
            canWrite = false
            errorMessage = "Saved ride history could not be read. The existing file was left untouched."
        }
    }

    @discardableResult
    private func commit(_ candidate: TripArchive) -> Bool {
        guard canWrite else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(candidate)
            try data.write(to: fileURL, options: .atomic)
            archive = candidate
            publishArchive()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Ride history could not be saved. Your existing ride file was left untouched."
            return false
        }
    }

    private func publishArchive() {
        trips = archive.trips.sorted { $0.startedAt > $1.startedAt }
        activeDraft = archive.activeDraft
    }
}

private struct TripArchive: Codable {
    var trips: [Ride] = []
    var activeDraft: RideDraft?
}
