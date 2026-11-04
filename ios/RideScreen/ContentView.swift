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

            NavigationStack {
                BikeView()
            }
            .tabItem {
                Label("Bike", systemImage: "bicycle.circle")
            }
        }
        .tint(RideScreenTheme.gold)
        .preferredColorScheme(.dark)
        .toolbarBackground(RideScreenTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(RideScreenTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct RideView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @EnvironmentObject private var store: TripStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 5) {
                    Text("CURRENT SPEED")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(RideScreenTheme.gold)
                    Text(recorder.speedKmh.formatted())
                        .font(RideScreenTheme.displayFont(size: 76))
                        .monospacedDigit()
                        .foregroundStyle(RideScreenTheme.primary)
                        .accessibilityLabel("Speed \(recorder.speedKmh) kilometers per hour")
                    Text("km/h")
                        .font(.headline)
                        .foregroundStyle(RideScreenTheme.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 174)
                .rideCard(padding: 18, radius: 22)

                HStack(spacing: 12) {
                    RideMetricCard(
                        title: "Distance",
                        value: (recorder.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1))),
                        unit: "km"
                    )
                    RideMetricCard(
                        title: "Moving time",
                        value: durationText(recorder.movingTime),
                        unit: nil
                    )
                }
                HStack {
                    Label(recorder.isRecording ? "Recording" : "Stopped", systemImage: recorder.isRecording ? "record.circle.fill" : "location.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(recorder.isRecording ? RideScreenTheme.live : RideScreenTheme.idle)
                    Spacer()
                    Text("Max \(Int((recorder.maxSpeedMetersPerSecond * 3.6).rounded())) km/h")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(RideScreenTheme.secondary)
                }
                .rideCard(padding: 14, radius: 16)

                Text(recorder.statusMessage)
                    .font(.callout)
                    .foregroundStyle(RideScreenTheme.secondary)
                    .rideCard(padding: 14, radius: 16)

                if recorder.isRecording, let accuracy = recorder.accuracyMeters {
                    Text("GPS accuracy about \(Int(accuracy.rounded())) m")
                        .font(.caption)
                        .foregroundStyle(RideScreenTheme.secondary)
                        .rideCard(padding: 12, radius: 16)
                }

                if recorder.needsLocationSettings {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Label("Open Location Settings", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                    .tint(RideScreenTheme.gold)
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(RideScreenTheme.error)
                        .rideCard(padding: 14, radius: 16)
                }

                if recorder.needsSaveRetry {
                    Button {
                        recorder.retrySave()
                    } label: {
                        Label("Retry saving ride", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(RideScreenTheme.gold)
                }

                Button {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording()
                    }
                } label: {
                    Label(recorder.isRecording ? "Stop ride" : "Start ride", systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(RidePrimaryButtonStyle(isDestructive: recorder.isRecording))
                .disabled(!recorder.isRecording && (!store.canRecord || recorder.needsSaveRetry))
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(RideScreenTheme.background.ignoresSafeArea())
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

private struct TripsView: View {
    @EnvironmentObject private var store: TripStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(RideScreenTheme.error)
                        .rideCard()
                }

                if store.trips.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bicycle")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(RideScreenTheme.gold)
                        Text("No rides yet")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(RideScreenTheme.primary)
                        Text("Recorded rides will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(RideScreenTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .rideCard(padding: 24)
                } else {
                    ForEach(store.trips) { ride in
                        NavigationLink {
                            TripDetailView(ride: ride)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(RideScreenTheme.primary)
                                HStack(spacing: 16) {
                                    Label("\((ride.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1)))) km", systemImage: "map")
                                    Label("\(durationText(ride.movingTime)) moving", systemImage: "clock")
                                }
                                .font(.caption)
                                .foregroundStyle(RideScreenTheme.secondary)
                                Text("Max \(Int((ride.maxSpeedMetersPerSecond * 3.6).rounded())) km/h")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(RideScreenTheme.secondary)
                            }
                            .rideCard(padding: 16, radius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(RideScreenTheme.background.ignoresSafeArea())
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
