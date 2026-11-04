// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private enum ProbeTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func probeExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ProbeTestFailure.assertion(message) }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest, StubURLProtocol) -> Void)?
    static var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            fatalError("StubURLProtocol.handler was not set")
        }
        handler(request, self)
    }

    override func stopLoading() {
        Self.stopped = true
    }

    func respond(status: Int, headers: [String: String] = [:], data: Data = Data(), finish: Bool = true) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
}

@main
struct CarPlayReceiverProbeTests {
    static func main() async throws {
        try await requestsOnlyTheFixedLoopbackEndpoint()
        try await mapsHTTPFailureToReceiverNotRunning()
        try await capsTheObservedBodyAt64KiB()
        try await timesOutAndCancelsANonEndingRequest()
        try await callerCancellationCancelsTheRequest()
        print("CarPlayReceiverProbeTests passed")
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func resetStub() {
        StubURLProtocol.handler = nil
        StubURLProtocol.stopped = false
    }

    private static func requestsOnlyTheFixedLoopbackEndpoint() async throws {
        resetStub()
        StubURLProtocol.handler = { request, stub in
            do {
                try probeExpect(request.url == URL(string: "http://127.0.0.1:8969/stream")!, "probe requested an unexpected endpoint")
                stub.respond(
                    status: 200,
                    headers: ["Content-Type": "video/h264"],
                    data: Data([0, 0, 1, 0x65, 0xAA])
                )
            } catch {
                stub.client?.urlProtocol(stub, didFailWithError: error)
            }
        }

        let summary = try await CarPlayReceiverProbe(timeout: .seconds(1)).run(session: makeSession())
        try probeExpect(summary.statusCode == 200, "probe lost the HTTP status")
        try probeExpect(summary.contentType == "video/h264", "probe lost the normalized content type")
        try probeExpect(summary.nalTypeCounts == [5: 1], "probe did not summarize the sampled stream")
    }

    private static func mapsHTTPFailureToReceiverNotRunning() async throws {
        resetStub()
        StubURLProtocol.handler = { _, stub in stub.respond(status: 503) }

        do {
            _ = try await CarPlayReceiverProbe(timeout: .seconds(1)).run(session: makeSession())
            throw ProbeTestFailure.assertion("HTTP 503 unexpectedly succeeded")
        } catch let error as ReceiverProbeError {
            try probeExpect(error == .notRunning, "HTTP 503 must map to receiver not running")
        }
    }

    private static func capsTheObservedBodyAt64KiB() async throws {
        resetStub()
        StubURLProtocol.handler = { _, stub in
            stub.respond(status: 200, data: Data(repeating: 0xAA, count: 70_000))
        }

        let summary = try await CarPlayReceiverProbe(timeout: .seconds(1)).run(session: makeSession())
        try probeExpect(summary.bytesObserved == 65_536, "probe retained more than its 64 KiB limit")
    }

    private static func timesOutAndCancelsANonEndingRequest() async throws {
        resetStub()
        StubURLProtocol.handler = { _, stub in stub.respond(status: 200, finish: false) }

        do {
            _ = try await CarPlayReceiverProbe(timeout: .milliseconds(50)).run(session: makeSession())
            throw ProbeTestFailure.assertion("non-ending request unexpectedly succeeded")
        } catch let error as ReceiverProbeError {
            try probeExpect(error == .timedOut, "non-ending request must time out")
        }
        try await Task.sleep(for: .milliseconds(20))
        try probeExpect(StubURLProtocol.stopped, "timed-out request was not cancelled")
    }

    private static func callerCancellationCancelsTheRequest() async throws {
        resetStub()
        StubURLProtocol.handler = { _, stub in stub.respond(status: 200, finish: false) }
        let session = makeSession()
        let task = Task {
            try await CarPlayReceiverProbe(timeout: .seconds(5)).run(session: session)
        }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()

        do {
            _ = try await task.value
            throw ProbeTestFailure.assertion("cancelled probe unexpectedly succeeded")
        } catch let error as ReceiverProbeError {
            try probeExpect(error == .cancelled, "caller cancellation must map to cancelled")
        }
        try await Task.sleep(for: .milliseconds(20))
        try probeExpect(StubURLProtocol.stopped, "caller cancellation did not stop the request")
    }
}
