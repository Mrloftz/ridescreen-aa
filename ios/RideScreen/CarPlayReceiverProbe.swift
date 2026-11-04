// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ReceiverProbeError: Error, Equatable {
    case notRunning
    case invalidResponse
    case timedOut
    case cancelled
}

struct CarPlayReceiverProbe {
    private static let fixedStreamURL = URL(string: "http://127.0.0.1:8969/stream")!

    let streamURL: URL
    let byteLimit: Int
    let timeout: Duration

    init(
        streamURL: URL = CarPlayReceiverProbe.fixedStreamURL,
        byteLimit: Int = 65_536,
        timeout: Duration = .seconds(3)
    ) {
        self.streamURL = streamURL
        self.byteLimit = byteLimit
        self.timeout = timeout
    }

    func run(session: URLSession = CarPlayReceiverProbe.makeSession()) async throws -> ReceiverStreamSummary {
        guard streamURL == Self.fixedStreamURL, byteLimit > 0 else {
            throw ReceiverProbeError.invalidResponse
        }

        do {
            return try await withThrowingTaskGroup(of: ReceiverStreamSummary.self) { group in
                group.addTask {
                    try await Self.fetchSummary(
                        from: streamURL,
                        byteLimit: byteLimit,
                        session: session
                    )
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ReceiverProbeError.timedOut
                }

                guard let result = try await group.next() else {
                    throw ReceiverProbeError.invalidResponse
                }
                group.cancelAll()
                return result
            }
        } catch let error as ReceiverProbeError {
            throw error
        } catch is CancellationError {
            throw ReceiverProbeError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw ReceiverProbeError.cancelled
        } catch {
            throw ReceiverProbeError.notRunning
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }

    private static func fetchSummary(
        from url: URL,
        byteLimit: Int,
        session: URLSession
    ) async throws -> ReceiverStreamSummary {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        #if canImport(FoundationNetworking)
        let (body, response) = try await session.data(for: request)
        let sample = Data(body.prefix(byteLimit))
        #else
        let (bytes, response) = try await session.bytes(for: request)
        var sample = Data()
        sample.reserveCapacity(byteLimit)
        for try await byte in bytes {
            sample.append(byte)
            if sample.count == byteLimit { break }
        }
        #endif
        guard let http = response as? HTTPURLResponse else {
            throw ReceiverProbeError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw ReceiverProbeError.notRunning
        }

        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, field in
            result[String(describing: field.key)] = String(describing: field.value)
        }
        return ReceiverStreamSummary.inspect(
            sample,
            headers: headers,
            statusCode: http.statusCode
        )
    }
}
