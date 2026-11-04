// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(Combine)
import Combine
#else
protocol ObservableObject: AnyObject {}

@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
#endif

enum ProjectionProbeState: Equatable {
    case idle
    case probing
    case ready
    case failed(String)
}

@MainActor
final class ProjectionProbeModel: ObservableObject {
    typealias Probe = () async throws -> ReceiverStreamSummary

    @Published private(set) var state: ProjectionProbeState = .idle
    @Published private(set) var summary: ReceiverStreamSummary?

    private let diagnostics: ProjectionDiagnostics
    private let appVersion: String
    private let device: String
    private let probe: Probe
    private var task: Task<Void, Never>?
    private var activeRunID: UUID?

    init(
        diagnostics: ProjectionDiagnostics,
        appVersion: String? = nil,
        device: String? = nil,
        probe: @escaping Probe = { try await CarPlayReceiverProbe().run() }
    ) {
        self.diagnostics = diagnostics
        self.appVersion = appVersion ?? Self.currentAppVersion
        self.device = device ?? Self.currentDevice
        self.probe = probe
    }

    func startProbe() {
        cancel(resetState: false)
        let runID = UUID()
        activeRunID = runID
        summary = nil
        state = .probing
        task = Task { [weak self] in
            guard let self else { return }
            await diagnostics.record(stage: .receiverDiscovery, message: "Probing loopback receiver")
            do {
                let result = try await probe()
                guard activeRunID == runID else { return }
                summary = result
                await diagnostics.record(
                    stage: .receiverStream,
                    message: Self.summaryLine(result)
                )
                state = .ready
            } catch let error as ReceiverProbeError {
                guard activeRunID == runID else { return }
                if error == .cancelled {
                    state = .idle
                } else {
                    let message = Self.correctiveMessage(for: error)
                    await diagnostics.record(stage: .error, message: message)
                    state = .failed(message)
                }
            } catch {
                guard activeRunID == runID else { return }
                let message = "Receiver probe failed. Start iCarCast This iPhone and retry."
                await diagnostics.record(stage: .error, message: message)
                state = .failed(message)
            }
        }
    }

    func cancel() {
        cancel(resetState: true)
    }

    func exportText() async -> String {
        await diagnostics.exportText(appVersion: appVersion, device: device)
    }

    private func cancel(resetState: Bool) {
        activeRunID = nil
        task?.cancel()
        task = nil
        if resetState {
            summary = nil
            state = .idle
        }
    }

    private static func correctiveMessage(for error: ReceiverProbeError) -> String {
        switch error {
        case .notRunning:
            return "iCarCast was not found. Start This iPhone in iCarCast, return here, and retry."
        case .invalidResponse:
            return "iCarCast returned an unexpected response. Keep it running and retry once."
        case .timedOut:
            return "iCarCast did not send stream data in time. Restart This iPhone and retry."
        case .cancelled:
            return "Probe cancelled."
        }
    }

    private static func summaryLine(_ summary: ReceiverStreamSummary) -> String {
        let types = summary.nalTypeCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        return "status=\(summary.statusCode ?? 0) contentType=\(summary.contentType ?? "unknown") bytes=\(summary.bytesObserved) framing=\(summary.framing.rawValue) nalTypes=\(types)"
    }

    private static var currentAppVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)): return "\(version) (\(build))"
        case let (.some(version), .none): return version
        case let (.none, .some(build)): return build
        case (.none, .none): return "unknown"
        }
    }

    private static var currentDevice: String {
        #if canImport(UIKit)
        return UIDevice.current.model + " / " + UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}

#if canImport(SwiftUI) && canImport(UIKit)
struct CarPlayProjectionView: View {
    @EnvironmentObject private var model: ProjectionProbeModel
    @Environment(\.dismiss) private var dismiss
    let bike: Bike

    @State private var reportToShare: DiagnosticShare?

    var body: some View {
        NavigationStack {
            List {
                Section("Before probing") {
                    prerequisite("Install and configure iCarCast")
                    prerequisite("Join \(bike.ssid) in Wi-Fi Settings")
                    prerequisite("Start This iPhone in iCarCast")
                    prerequisite("Return here and tap Probe iCarCast")
                }

                Section("Receiver checkpoint") {
                    LabeledContent("Stage", value: stageText)
                    if model.state == .probing { ProgressView() }
                    if let summary = model.summary {
                        LabeledContent("HTTP", value: String(summary.statusCode ?? 0))
                        LabeledContent("Content", value: summary.contentType ?? "Unknown")
                        LabeledContent("Sample", value: "\(summary.bytesObserved) bytes")
                        LabeledContent("Framing", value: summary.framing.rawValue)
                        LabeledContent("NAL types", value: nalSummary(summary))
                    }
                    if case .failed(let message) = model.state {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Probe iCarCast") { model.startProbe() }
                        .disabled(model.state == .probing)
                    if case .failed = model.state {
                        Button("Retry") { model.startProbe() }
                    }
                    Button("Cancel", role: .cancel) { model.cancel() }
                        .disabled(model.state == .idle)
                    Button("Share diagnostic") {
                        Task {
                            let text = await model.exportText()
                            reportToShare = DiagnosticShare(text: text)
                        }
                    }
                }
            }
            .navigationTitle("Project CarPlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $reportToShare) { report in
                ActivityShareView(items: [report.text])
            }
            .onDisappear { model.cancel() }
        }
    }

    private func prerequisite(_ text: String) -> some View {
        Label(text, systemImage: "checklist")
    }

    private var stageText: String {
        switch model.state {
        case .idle: return "Ready to probe"
        case .probing: return "Receiver discovery"
        case .ready: return "Receiver stream detected"
        case .failed: return "Probe failed"
        }
    }

    private func nalSummary(_ summary: ReceiverStreamSummary) -> String {
        let value = summary.nalTypeCounts.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
        return value.isEmpty ? "None detected" : value
    }
}

private struct DiagnosticShare: Identifiable {
    let id = UUID()
    let text: String
}

private struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
