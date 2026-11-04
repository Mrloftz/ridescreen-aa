// SPDX-License-Identifier: AGPL-3.0-or-later
import AVFoundation
import SwiftUI
import UIKit

struct BikeView: View {
    @EnvironmentObject private var store: BikeStore
    @State private var showingAddFlow = false
    @State private var notice: BikeNotice?
    @State private var bikeToRemove: Bike?
    @State private var connectingBikeID: UUID?

    var body: some View {
        List {
            Section {
                Button(action: requestCameraAndScan) {
                    Label("Scan bike QR", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityHint("Scan a MotoPlay or EasyConnect Wi-Fi pairing code")
            }

            if let error = store.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Saved bikes") {
                if store.bikes.isEmpty {
                    Text("No bikes saved yet. Scan the pairing QR shown on the dash.")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.bikes) { bike in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(bike.name).font(.headline)
                        Label(bike.ssid, systemImage: "wifi")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button {
                                connect(bike)
                            } label: {
                                Label(
                                    connectingBikeID == bike.id ? "Joining" : "Join Wi-Fi",
                                    systemImage: "wifi"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(connectingBikeID != nil)

                            Button(role: .destructive) {
                                bikeToRemove = bike
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Remove \(bike.name)")
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("Bike")
        .sheet(isPresented: $showingAddFlow) {
            BikeAddFlowView()
                .environmentObject(store)
        }
        .alert(item: $notice) { notice in
            if notice.opensSettings {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Open Settings"), action: openAppSettings),
                    secondaryButton: .cancel()
                )
            }
            return Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog("Remove saved bike?", isPresented: Binding(
            get: { bikeToRemove != nil },
            set: { if !$0 { bikeToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: removeBike)
            Button("Cancel", role: .cancel) { bikeToRemove = nil }
        } message: {
            Text("This removes the saved bike and asks iOS to remove RideScreen's Wi-Fi configuration. Networks added elsewhere remain in Settings.")
        }
    }

    private func requestCameraAndScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingAddFlow = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingAddFlow = true
                    } else {
                        notice = BikeNotice(
                            title: "Camera access required",
                            message: "Allow camera access in Settings to scan the bike's pairing QR.",
                            opensSettings: true
                        )
                    }
                }
            }
        case .denied, .restricted:
            notice = BikeNotice(
                title: "Camera access required",
                message: "Allow camera access in Settings to scan the bike's pairing QR.",
                opensSettings: true
            )
        @unknown default:
            notice = BikeNotice(title: "Camera unavailable", message: "RideScreen could not access the camera.")
        }
    }

    private func connect(_ bike: Bike) {
        connectingBikeID = bike.id
        Task {
            defer { connectingBikeID = nil }
            do {
                let password = try store.password(for: bike)
                let result = await BikeWiFiConnector.join(ssid: bike.ssid, password: password)
                notice = BikeNotice(title: "Bike Wi-Fi", message: result.message)
            } catch {
                notice = BikeNotice(title: "Bike Wi-Fi", message: error.localizedDescription)
            }
        }
    }

    private func removeBike() {
        guard let bike = bikeToRemove else { return }
        do {
            try store.remove(bike)
            BikeWiFiConnector.remove(ssid: bike.ssid)
        } catch {
            notice = BikeNotice(title: "Could not remove bike", message: error.localizedDescription)
        }
        bikeToRemove = nil
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct BikeAddFlowView: View {
    @EnvironmentObject private var store: BikeStore
    @Environment(\.dismiss) private var dismiss
    @State private var pairing: BikePairing?
    @State private var scanError: String?
    @State private var scanAttempt = 0

    var body: some View {
        NavigationStack {
            Group {
                if let pairing {
                    BikePairingReviewView(pairing: pairing)
                        .environmentObject(store)
                } else {
                    QRScannerView { raw in
                        switch BikePairing.parse(raw) {
                        case .success(let pairing):
                            self.pairing = pairing
                        case .failure(let error):
                            scanError = error.localizedDescription
                        }
                    }
                    .id(scanAttempt)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("Point the camera at the MotoPlay or EasyConnect pairing QR.")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.65))
                    }
                }
            }
            .navigationTitle(pairing == nil ? "Scan bike QR" : "Review bike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("QR not supported", isPresented: Binding(
                get: { scanError != nil },
                set: { if !$0 { scanError = nil } }
            )) {
                Button("Scan again", role: .cancel) {
                    scanError = nil
                    scanAttempt += 1
                }
            } message: {
                Text(scanError ?? "")
            }
        }
    }
}

private struct BikePairingReviewView: View {
    @EnvironmentObject private var store: BikeStore
    @Environment(\.dismiss) private var dismiss
    let pairing: BikePairing

    @State private var name = ""
    @State private var savedBike: Bike?
    @State private var isJoining = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Detected Wi-Fi") {
                LabeledContent("Network", value: pairing.ssid)
                TextField("Bike name", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section {
                Text("iOS will ask before joining this Wi-Fi network. This setup only joins Wi-Fi; it does not connect to the bike display or start projection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section("Status") {
                    Text(statusMessage)
                        .font(.callout)
                }
            }

            Section {
                Button {
                    saveAndJoin()
                } label: {
                    HStack {
                        Spacer()
                        if isJoining { ProgressView().padding(.trailing, 8) }
                        Text(savedBike == nil ? "Save and Join Wi-Fi" : "Try Wi-Fi Again")
                        Spacer()
                    }
                }
                .disabled(isJoining)

                if savedBike != nil {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { name = pairing.suggestedName }
    }

    private func saveAndJoin() {
        isJoining = true
        statusMessage = nil
        Task {
            defer { isJoining = false }
            do {
                let bike: Bike
                if let savedBike {
                    bike = savedBike
                } else {
                    bike = try store.add(pairing, name: name)
                    savedBike = bike
                }
                let password = try store.password(for: bike)
                let result = await BikeWiFiConnector.join(ssid: bike.ssid, password: password)
                statusMessage = result.message
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

private struct BikeNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var opensSettings = false
}
