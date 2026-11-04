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
            await diagnostics.record(
                stage: .receiverDiscovery,
                message: "Checking hard-coded local URL http://127.0.0.1:8969/stream"
            )
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
                let message = "The local URL check failed unexpectedly. This result does not confirm whether iCarCast is running."
                await diagnostics.record(stage: .error, message: message)
                state = .failed(message)
            }
        }
    }

    func cancel() {
        cancel(resetState: true)
    }

    func recordWiFiResult(_ message: String, ssidLength: Int) async {
        await diagnostics.record(
            stage: .bikeProbe,
            message: "NEHotspotConfiguration; SSID length=\(ssidLength); \(message)"
        )
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
            return "No usable response from the hard-coded local URL 127.0.0.1:8969/stream. This does not confirm whether iCarCast is running."
        case .invalidResponse:
            return "The local URL responded with data RideScreen cannot read. This check does not verify iCarCast or the bike display."
        case .timedOut:
            return "No data arrived from the hard-coded local URL 127.0.0.1:8969/stream. This does not confirm whether iCarCast is running."
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RideSectionHeading(
                        title: "CarPlay diagnostics",
                        subtitle: "\(bike.name) · \(bike.ssid)"
                    )

                    VStack(alignment: .leading, spacing: 13) {
                        Text("ABOUT THIS CHECK")
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(RideScreenTheme.gold)
                        diagnosticNote("RideScreen sends an experimental request to 127.0.0.1:8969/stream on this iPhone.")
                        diagnosticNote("This undocumented local URL does not confirm whether iCarCast is running.")
                        diagnosticNote("This check does not send CarPlay video to the Zontes display.")
                    }
                    .rideCard(padding: 17)

                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("LOCAL URL RESULT")
                                .font(.caption.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(RideScreenTheme.gold)
                            Spacer()
                            Circle()
                                .fill(statusColor)
                                .frame(width: 9, height: 9)
                            Text(stageText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor)
                        }

                        if model.state == .probing {
                            HStack(spacing: 10) {
                                ProgressView().tint(RideScreenTheme.gold)
                                Text("Checking local URL…")
                                    .font(.subheadline)
                                    .foregroundStyle(RideScreenTheme.secondary)
                            }
                            .padding(.vertical, 4)
                        }

                        if let summary = model.summary {
                            checkpointRow("HTTP", value: String(summary.statusCode ?? 0))
                            checkpointRow("Content", value: summary.contentType ?? "Unknown")
                            checkpointRow("Sample", value: "\(summary.bytesObserved) bytes")
                            checkpointRow("Framing", value: summary.framing.rawValue)
                            checkpointRow("NAL types", value: nalSummary(summary))
                        }

                        if case .failed(let message) = model.state {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(RideScreenTheme.error)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .rideCard(padding: 17)

                    Button {
                        model.startProbe()
                    } label: {
                        Label("Check local URL", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(RidePrimaryButtonStyle())
                    .disabled(model.state == .probing)

                    HStack(spacing: 10) {
                        if case .failed = model.state {
                            Button {
                                model.startProbe()
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(RideSecondaryButtonStyle())
                        }

                        Button {
                            Task {
                                let text = await model.exportText()
                                reportToShare = DiagnosticShare(text: text)
                            }
                        } label: {
                            Label("Share diagnostic", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(RideSecondaryButtonStyle())
                    }

                    Button("Cancel probe") { model.cancel() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RideScreenTheme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .disabled(model.state == .idle)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            .background(RideScreenTheme.background.ignoresSafeArea())
            .navigationTitle("CarPlay diagnostics")
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
        .toolbarBackground(RideScreenTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func diagnosticNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(RideScreenTheme.gold)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(RideScreenTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkpointRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(RideScreenTheme.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(RideScreenTheme.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .idle: return RideScreenTheme.idle
        case .probing: return RideScreenTheme.busy
        case .ready: return RideScreenTheme.live
        case .failed: return RideScreenTheme.error
        }
    }

    private var stageText: String {
        switch model.state {
        case .idle: return "Ready to check"
        case .probing: return "Checking URL"
        case .ready: return "Local URL responded"
        case .failed: return "No usable response"
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
