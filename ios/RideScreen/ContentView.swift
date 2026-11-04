// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                RideView()
                    .navigationTitle("Ride")
            }
            .tabItem {
                Label("Ride", systemImage: "bicycle")
            }

            NavigationStack {
                TripsView()
                    .navigationTitle("Trips")
            }
            .tabItem {
                Label("Trips", systemImage: "list.bullet.rectangle")
            }
        }
    }
}

private struct RideView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @EnvironmentObject private var store: TripStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(recorder.speedKmh.formatted())
                        .font(.system(size: 76, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("Speed \(recorder.speedKmh) kilometers per hour")
                    Text("km/h")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))

                HStack(spacing: 12) {
                    MetricCard(
                        title: "Distance",
                        value: (recorder.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1))),
                        unit: "km"
                    )
                    MetricCard(
                        title: "Moving time",
                        value: durationText(recorder.movingTime),
                        unit: nil
                    )
                }
                HStack {
                    Label(recorder.isRecording ? "Recording" : "Stopped", systemImage: recorder.isRecording ? "record.circle.fill" : "location.circle")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Max \(Int((recorder.maxSpeedMetersPerSecond * 3.6).rounded())) km/h")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(recorder.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if recorder.isRecording, let accuracy = recorder.accuracyMeters {
                    Text("GPS accuracy about \(Int(accuracy.rounded())) m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if recorder.needsLocationSettings {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Label("Open Location Settings", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if recorder.needsSaveRetry {
                    Button {
                        recorder.retrySave()
                    } label: {
                        Label("Retry saving ride", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording()
                    }
                } label: {
                    Label(recorder.isRecording ? "Stop ride" : "Start ride", systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .green)
                .disabled(!recorder.isRecording && (!store.canRecord || recorder.needsSaveRetry))
            }
            .padding()
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct TripsView: View {
    @EnvironmentObject private var store: TripStore

    var body: some View {
        List {
            if let error = store.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if store.trips.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bicycle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No rides yet")
                        .font(.headline)
                    Text("Recorded rides will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .listRowSeparator(.hidden)
            } else {
                ForEach(store.trips) { ride in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        HStack(spacing: 16) {
                            Label("\((ride.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1)))) km", systemImage: "map")
                            Label("\(durationText(ride.movingTime)) moving", systemImage: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text("Max \(Int((ride.maxSpeedMetersPerSecond * 3.6).rounded())) km/h")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
