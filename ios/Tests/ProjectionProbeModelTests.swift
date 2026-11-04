// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

private enum ModelTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func modelExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ModelTestFailure.assertion(message) }
}

@main
struct ProjectionProbeModelTests {
    static func main() async throws {
        try await readyFlowAndExportAreBounded()
        try await receiverFailureIsRetryable()
        try await cancellationReturnsToIdle()
        print("ProjectionProbeModelTests passed")
    }

    @MainActor
    private static func readyFlowAndExportAreBounded() async throws {
        let diagnostics = ProjectionDiagnostics()
        let expected = ReceiverStreamSummary(
            statusCode: 200,
            contentType: "video/h264",
            bytesObserved: 4_096,
            framing: .annexB,
            nalTypeCounts: [5: 1, 7: 1, 8: 1]
        )
        let model = ProjectionProbeModel(
            diagnostics: diagnostics,
            appVersion: "test-1",
            device: "test-device",
            probe: { expected }
        )

        try modelExpect(model.state == .idle, "model did not start idle")
        model.startProbe()
        try modelExpect(model.state == .probing, "model did not enter probing synchronously")
        try await waitUntil { model.state == .ready }
        try modelExpect(model.summary == expected, "model lost the receiver summary")

        let report = await model.exportText()
        try modelExpect(report.contains("App: test-1"), "export omitted app metadata")
        try modelExpect(report.contains("Device: test-device"), "export omitted device metadata")
        try modelExpect(report.contains("bytes=4096"), "export omitted the bounded byte count")
        try modelExpect(!report.contains("sampledBytes"), "export included sampled video bytes")
    }

    @MainActor
    private static func receiverFailureIsRetryable() async throws {
        let model = ProjectionProbeModel(
            diagnostics: ProjectionDiagnostics(),
            probe: { throw ReceiverProbeError.notRunning }
        )

        model.startProbe()
        try await waitUntil {
            if case .failed = model.state { return true }
            return false
        }
        if case .failed(let message) = model.state {
            try modelExpect(message.contains("iCarCast"), "receiver failure lacks corrective action")
        } else {
            throw ModelTestFailure.assertion("receiver failure was not retryable")
        }
    }

    @MainActor
    private static func cancellationReturnsToIdle() async throws {
        let model = ProjectionProbeModel(
            diagnostics: ProjectionDiagnostics(),
            probe: {
                try await Task.sleep(for: .seconds(5))
                throw ReceiverProbeError.notRunning
            }
        )

        model.startProbe()
        try modelExpect(model.state == .probing, "cancellation test did not begin probing")
        model.cancel()
        try modelExpect(model.state == .idle, "cancel did not restore idle state")
    }

    @MainActor
    private static func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                throw ModelTestFailure.assertion("timed out waiting for model state")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
