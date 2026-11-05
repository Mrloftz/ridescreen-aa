// SPDX-License-Identifier: AGPL-3.0-or-later
import AVFoundation
import SwiftUI
import UIKit

struct BikeView: View {
    @EnvironmentObject private var store: BikeStore
    @EnvironmentObject private var projectionModel: ProjectionProbeModel
    @State private var showingAddFlow = false
    @State private var notice: BikeNotice?
    @State private var bikeToRemove: Bike?
    @State private var connectingBikeID: UUID?
    @State private var projectingBike: Bike?
    @State private var manualWiFiSetup: BikeManualWiFiSetup?
    @State private var manualJoinConfirmedBikeIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 13) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(RideScreenTheme.gold)
                        .frame(width: 54, height: 54)
                        .background(RideScreenTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Garage")
                            .font(.title.weight(.bold))
                            .foregroundStyle(RideScreenTheme.primary)
                        Text("Manage your connected bikes")
                            .font(.subheadline)
                            .foregroundStyle(RideScreenTheme.secondary)
                    }
                }

                Button(action: requestCameraAndScan) {
                    Label("Scan bike QR", systemImage: "qrcode.viewfinder")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(RidePrimaryButtonStyle())
                .accessibilityHint("Scan a MotoPlay or EasyConnect Wi-Fi pairing code")

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(RideScreenTheme.error)
                        .rideCard()
                }

                RideSectionHeading(title: "Saved bikes", subtitle: "Your motorcycle Wi-Fi profiles")

                if store.bikes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No bikes saved yet", systemImage: "bicycle")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(RideScreenTheme.primary)
                        Text("Scan the pairing QR shown on the dash to add your bike.")
                            .font(.subheadline)
                            .foregroundStyle(RideScreenTheme.secondary)
                    }
                    .rideCard(padding: 18)
                }

                ForEach(store.bikes) { bike in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "bicycle")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(RideScreenTheme.gold)
                                .frame(width: 48, height: 48)
                                .background(RideScreenTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bike.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(RideScreenTheme.primary)
                                    .lineLimit(2)
                                Label(bike.ssid, systemImage: "wifi")
                                    .font(.caption)
                                    .foregroundStyle(RideScreenTheme.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            Button(role: .destructive) {
                                bikeToRemove = bike
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(RideScreenTheme.error)
                                    .frame(width: 40, height: 40)
                                    .background(RideScreenTheme.elevated, in: Circle())
                            }
                            .accessibilityLabel("Remove \(bike.name)")
                        }

                        HStack(spacing: 10) {
                            Button {
                                connect(bike)
                            } label: {
                                Label(connectingBikeID == bike.id ? "Joining" : "Join Wi-Fi", systemImage: "wifi")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(RidePrimaryButtonStyle())
                            .disabled(connectingBikeID != nil)

                            Button {
                                projectingBike = bike
                            } label: {
                                Label("CarPlay check", systemImage: "waveform.path.ecg")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(RideSecondaryButtonStyle())
                        }

                        Button {
                            showManualWiFiSetup(for: bike)
                        } label: {
                            Label("Manual Wi-Fi setup", systemImage: "list.number")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(RideSecondaryButtonStyle())

                        if let setup = manualWiFiSetup, setup.bike.id == bike.id {
                            BikeManualWiFiInstructions(
                                ssid: bike.ssid,
                                password: setup.password,
                                onJoined: {
                                    manualJoinConfirmedBikeIDs.insert(bike.id)
                                    manualWiFiSetup = nil
                                }
                            )
                        }

                        if manualJoinConfirmedBikeIDs.contains(bike.id) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Manual Wi-Fi join confirmed by you", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(RideScreenTheme.primary)
                                Text("RideScreen cannot verify the current Wi-Fi network, and this build does not connect to the bike display.")
                                    .font(.caption)
                                    .foregroundStyle(RideScreenTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RideScreenTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .rideCard(padding: 15, radius: 20)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(RideScreenTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAddFlow) {
            BikeAddFlowView()
                .environmentObject(store)
        }
        .sheet(item: $projectingBike) { bike in
            CarPlayProjectionView(bike: bike)
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
        manualJoinConfirmedBikeIDs.remove(bike.id)
        if manualWiFiSetup?.bike.id == bike.id {
            manualWiFiSetup = nil
        }
        connectingBikeID = bike.id
        Task {
            defer { connectingBikeID = nil }
            do {
                let password = try store.password(for: bike)
                let result = await BikeWiFiConnector.join(ssid: bike.ssid, password: password)
                await projectionModel.recordWiFiResult(result.message, ssidLength: bike.ssid.utf8.count)
                if case .failed(let message) = result {
                    manualWiFiSetup = BikeManualWiFiSetup(bike: bike, password: password)
                    notice = BikeNotice(
                        title: "Automatic Wi-Fi setup failed",
                        message: "\(message) Manual steps are now shown on the bike card."
                    )
                } else {
                    notice = BikeNotice(title: "Bike Wi-Fi", message: result.message)
                }
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
            manualJoinConfirmedBikeIDs.remove(bike.id)
            if manualWiFiSetup?.bike.id == bike.id {
                manualWiFiSetup = nil
            }
        } catch {
            notice = BikeNotice(title: "Could not remove bike", message: error.localizedDescription)
        }
        bikeToRemove = nil
    }

    private func showManualWiFiSetup(for bike: Bike) {
        do {
            manualJoinConfirmedBikeIDs.remove(bike.id)
            manualWiFiSetup = BikeManualWiFiSetup(
                bike: bike,
                password: try store.password(for: bike)
            )
        } catch {
            notice = BikeNotice(title: "Wi-Fi password unavailable", message: error.localizedDescription)
        }
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
        .toolbarBackground(RideScreenTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct BikePairingReviewView: View {
    @EnvironmentObject private var store: BikeStore
    @EnvironmentObject private var projectionModel: ProjectionProbeModel
    @Environment(\.dismiss) private var dismiss
    let pairing: BikePairing

    @State private var name = ""
    @State private var savedBike: Bike?
    @State private var isJoining = false
    @State private var statusMessage: String?
    @State private var showingManualWiFiInstructions = false
    @State private var manualJoinConfirmed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RideSectionHeading(title: "Detected Wi-Fi", subtitle: "Confirm the bike details")

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NETWORK")
                            .font(.caption.weight(.semibold))
                            .tracking(0.7)
                            .foregroundStyle(RideScreenTheme.secondary)
                        Label(pairing.ssid, systemImage: "wifi")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(RideScreenTheme.primary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    Rectangle()
                        .fill(RideScreenTheme.outline)
                        .frame(height: 1)

                    TextField("Bike name", text: $name)
                        .font(.body)
                        .foregroundStyle(RideScreenTheme.primary)
                        .textInputAutocapitalization(.words)
                }
                .rideCard(padding: 17)

                Label {
                    Text("RideScreen asks iOS to join this Wi-Fi. If automatic setup fails, use the manual Wi-Fi steps below. Joining Wi-Fi alone does not connect to the bike display or send CarPlay to it.")
                        .font(.footnote)
                        .foregroundStyle(RideScreenTheme.secondary)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(RideScreenTheme.gold)
                }
                .rideCard(padding: 16, radius: 18)

                if let statusMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STATUS")
                            .font(.caption.weight(.bold))
                            .tracking(0.7)
                            .foregroundStyle(RideScreenTheme.gold)
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(RideScreenTheme.primary)
                            .textSelection(.enabled)
                    }
                    .rideCard(padding: 16, radius: 18)
                }

                if showingManualWiFiInstructions {
                    BikeManualWiFiInstructions(
                        ssid: pairing.ssid,
                        password: pairing.password,
                        onJoined: {
                            manualJoinConfirmed = true
                            showingManualWiFiInstructions = false
                            statusMessage = nil
                        }
                    )
                }

                if manualJoinConfirmed {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Manual Wi-Fi join confirmed by you", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(RideScreenTheme.primary)
                        Text("RideScreen cannot verify the current Wi-Fi network, and this build does not connect to the bike display.")
                            .font(.caption)
                            .foregroundStyle(RideScreenTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RideScreenTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    saveAndJoin()
                } label: {
                    HStack(spacing: 10) {
                        if isJoining { ProgressView().tint(RideScreenTheme.onBrand) }
                        Text(savedBike == nil ? "Save and Join Wi-Fi" : "Try Wi-Fi Again")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(RidePrimaryButtonStyle())
                .disabled(isJoining)

                if savedBike != nil {
                    Button {
                        if !showingManualWiFiInstructions {
                            manualJoinConfirmed = false
                        }
                        showingManualWiFiInstructions.toggle()
                    } label: {
                        Label(
                            showingManualWiFiInstructions ? "Hide Wi-Fi instructions" : "Manual Wi-Fi setup",
                            systemImage: "list.number"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(RideSecondaryButtonStyle())

                    Button("Done") { dismiss() }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(RideSecondaryButtonStyle())
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(RideScreenTheme.background.ignoresSafeArea())
        .onAppear { name = pairing.suggestedName }
    }

    private func saveAndJoin() {
        isJoining = true
        statusMessage = nil
        manualJoinConfirmed = false
        showingManualWiFiInstructions = false
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
                await projectionModel.recordWiFiResult(result.message, ssidLength: bike.ssid.utf8.count)
                statusMessage = result.message
                if case .failed = result {
                    showingManualWiFiInstructions = true
                }
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

private struct BikeManualWiFiSetup {
    let bike: Bike
    let password: String
}

private struct BikeManualWiFiInstructions: View {
    let ssid: String
    let password: String
    let onJoined: () -> Void

    @State private var passwordCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Join through iPhone Wi-Fi settings", systemImage: "wifi")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RideScreenTheme.primary)

            Text("Copy the password, open Settings > Wi-Fi, and choose \(ssid). Paste the password if iOS asks, then return to RideScreen.")
                .font(.footnote)
                .foregroundStyle(RideScreenTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIPasteboard.general.string = password
                passwordCopied = true
            } label: {
                Label(passwordCopied ? "Password copied" : "Copy Wi-Fi password", systemImage: passwordCopied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(RidePrimaryButtonStyle())

            Button(action: onJoined) {
                Label("I joined this Wi-Fi", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(RideSecondaryButtonStyle())

            Text("Check Settings > Wi-Fi to confirm the iPhone joined this network. RideScreen cannot verify the connection from this screen.")
                .font(.caption)
                .foregroundStyle(RideScreenTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(RideScreenTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(RideScreenTheme.outline, lineWidth: 1)
        }
    }
}
