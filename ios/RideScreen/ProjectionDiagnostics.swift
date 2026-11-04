// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum ProjectionStage: String, Codable {
    case receiverDiscovery
    case receiverStream
    case bikeProbe
    case controlHandshake
    case mediaNegotiation
    case frameDelivery
    case stopped
    case error
}

struct ProjectionEvent: Codable, Equatable {
    let timestamp: Date
    let stage: ProjectionStage
    let message: String
}

enum DiagnosticRedactor {
    private static let keyedSecret = try! NSRegularExpression(
        pattern: #"(?i)"?(ssid|password|pwd|mac|huid|token)"?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,&}]+)"#
    )
    private static let urlQuery = try! NSRegularExpression(
        pattern: #"(?i)(https?://[^\s?]+)\?[^\s]+"#
    )

    static func redact(_ text: String) -> String {
        var result = replace(keyedSecret, in: text, with: "$1=<redacted>")
        result = replace(urlQuery, in: result, with: "$1?<redacted>")
        return result
    }

    private static func replace(
        _ expression: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template
        )
    }
}

actor ProjectionDiagnostics {
    private let maxEvents: Int
    private var storedEvents: [ProjectionEvent] = []

    init(maxEvents: Int = 500) {
        self.maxEvents = max(1, maxEvents)
    }

    func record(stage: ProjectionStage, message: String) {
        storedEvents.append(ProjectionEvent(
            timestamp: .now,
            stage: stage,
            message: DiagnosticRedactor.redact(message)
        ))
        if storedEvents.count > maxEvents {
            storedEvents.removeFirst(storedEvents.count - maxEvents)
        }
    }

    func events() -> [ProjectionEvent] {
        storedEvents
    }

    func clear() {
        storedEvents.removeAll(keepingCapacity: true)
    }

    func exportText(appVersion: String, device: String) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "RideScreen CarPlay diagnostic",
            "App: \(DiagnosticRedactor.redact(appVersion))",
            "Device: \(DiagnosticRedactor.redact(device))"
        ]
        lines.append(contentsOf: storedEvents.map { event in
            "\(formatter.string(from: event.timestamp)) [\(event.stage.rawValue)] \(event.message)"
        })
        return lines.joined(separator: "\n")
    }
}
