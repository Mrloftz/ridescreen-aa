// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
struct ReceiverProbeCoreTests {
    static func main() async throws {
        try await diagnosticsDropOnlyTheOldestEvents()
        try redactionRemovesSecretsButKeepsUsefulText()
        try summaryRecognizesBothAnnexBStartCodes()
        try summaryRejectsIncompleteAndUnrecognizedBytes()
        try summaryKeepsOnlyNormalizedMetadata()
        print("ReceiverProbeCoreTests passed")
    }

    private static func diagnosticsDropOnlyTheOldestEvents() async throws {
        let diagnostics = ProjectionDiagnostics(maxEvents: 500)
        for index in 0...500 {
            await diagnostics.record(stage: .receiverDiscovery, message: "event \(index)")
        }

        let events = await diagnostics.events()
        try expect(events.count == 500, "diagnostics must retain exactly 500 events")
        try expect(events.first?.message == "event 1", "diagnostics must discard the oldest event")
        try expect(events.last?.message == "event 500", "diagnostics must retain the newest event")
    }

    private static func redactionRemovesSecretsButKeepsUsefulText() throws {
        let input = "stage ready ssid=BikeNet pwd:12345678 password=secret mac=AA:BB:CC:DD:EE:FF HUID=ABC123 token=qwerty http://127.0.0.1:8969/stream?auth=hidden&mode=video"
        let redacted = DiagnosticRedactor.redact(input)

        for secret in ["BikeNet", "12345678", "secret", "AA:BB:CC:DD:EE:FF", "ABC123", "qwerty", "hidden"] {
            try expect(!redacted.contains(secret), "redaction leaked \(secret)")
        }
        try expect(redacted.contains("stage ready"), "redaction removed harmless diagnostic text")
        try expect(redacted.contains("http://127.0.0.1:8969/stream?<redacted>"), "URL path should remain useful while its query is redacted")
    }

    private static func summaryRecognizesBothAnnexBStartCodes() throws {
        let bytes = Data([
            0x00, 0x00, 0x00, 0x01, 0x67, 0x11,
            0x00, 0x00, 0x01, 0x68, 0x22,
            0x00, 0x00, 0x00, 0x01, 0x65, 0x33
        ])

        let summary = ReceiverStreamSummary.inspect(bytes, headers: [:], statusCode: 200)
        try expect(summary.framing == .annexB, "both Annex-B prefix lengths must be recognized")
        try expect(summary.nalTypeCounts == [5: 1, 7: 1, 8: 1], "NAL types must be counted without retaining payloads")
    }

    private static func summaryRejectsIncompleteAndUnrecognizedBytes() throws {
        let incomplete = ReceiverStreamSummary.inspect(Data([0x00, 0x00, 0x01]), headers: [:], statusCode: nil)
        let random = ReceiverStreamSummary.inspect(Data([0xDE, 0xAD, 0xBE, 0xEF]), headers: [:], statusCode: nil)

        try expect(incomplete.framing == .unknown, "a start code without a NAL header is incomplete")
        try expect(incomplete.nalTypeCounts.isEmpty, "incomplete bytes must not invent a NAL")
        try expect(random.framing == .unknown, "random bytes must remain unknown")
    }

    private static func summaryKeepsOnlyNormalizedMetadata() throws {
        let data = Data([0x00, 0x00, 0x01, 0x65, 0xAA])
        let summary = ReceiverStreamSummary.inspect(
            data,
            headers: ["CONTENT-TYPE": "Video/H264; charset=binary", "X-Receiver-Token": "must-not-survive"],
            statusCode: 206
        )

        try expect(summary.statusCode == 206, "HTTP status must be retained")
        try expect(summary.contentType == "video/h264", "content type must be normalized without parameters")
        try expect(summary.bytesObserved == 5, "observed byte count must be exact")
        try expect(summary.nalTypeCounts == [5: 1], "NAL summary must retain only the type count")
    }
}
