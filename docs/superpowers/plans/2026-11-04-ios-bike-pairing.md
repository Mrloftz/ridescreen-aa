# iOS Bike Pairing Implementation Plan

> **For agentic workers:** Implement inline in the existing `feat/ios-foundation` worktree. This plan is one iOS pairing slice.

**Goal:** Let riders scan, save, and ask iOS to join a Carbit Wi-Fi AP for a Zontes 125X/125V.

**Architecture:** Parse Carbit QR data into a validated pairing value. Save non-secret bike metadata in Application Support and its password in Keychain. Use AVFoundation for QR scanning and NetworkExtension for the system-approved Wi-Fi join.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, NetworkExtension, Security; iOS 16.0.

**Spec:** `docs/superpowers/specs/2026-11-04-ios-bike-pairing-design.md`

## Global Constraints

- iOS 16.0 minimum and Swift language mode 5.
- No third-party dependencies.
- Camera access begins only after Scan is tapped.
- Wi-Fi changes require the rider's explicit approval through iOS.
- Credentials stay out of JSON metadata and logs.
- P2P, phone-hosted hotspot, projection, and CarPlay remain out of scope.

## Files

- Create `ios/RideScreen/BikePairing.swift` for the validated QR model/parser, local metadata store, Keychain credentials, and hotspot join helper.
- Create `ios/RideScreen/QRScannerView.swift` for the AVFoundation camera preview and QR callback.
- Create `ios/RideScreen/BikeView.swift` for scan, review, saved bikes, retry, and removal UI.
- Modify `ios/RideScreen/ContentView.swift` to add the Bike tab and environment store.
- Modify `ios/RideScreen/RideScreenApp.swift` to own the bike store.
- Modify `ios/RideScreen/Info.plist` for the camera purpose string.
- Create `ios/RideScreen/RideScreen.entitlements` and reference it in both Xcode configurations for Hotspot Configuration.
- Modify `ios/RideScreen.xcodeproj/project.pbxproj` to include sources and entitlements.
- Update `ios/README.md` with the feature and required device validation.

## Review Focus

- Percent-encoded SSID/password values must be decoded once and validated before saving.
- Carbit action values that include AP plus P2P remain usable over AP; P2P-only and phone-hotspot QR codes are rejected with useful guidance.
- Camera denial and unavailable camera must leave the Bike tab usable.
- A user denial or invalid password must not be presented as a successful connection.
- A successful `apply` means iOS accepted the configuration, not that the dash protocol is connected.

### Task 1: Add safe bike pairing and Wi-Fi primitives

**Files:** Create `BikePairing.swift`; add the entitlement; update the project file.

- [x] Define the Carbit QR value and parse SSID/password/name/action from query parameters, requiring the AP bit and rejecting phone-hotspot/P2P-only payloads.
- [x] Add local metadata persistence with atomic writes and Keychain-only passwords.
- [x] Add a NetworkExtension helper for persistent Wi-Fi configuration; distinguish already-associated, denied, and generic failure.
- [x] Add and wire the Hotspot Configuration entitlement.
- [x] Review parser boundaries, secret handling, and API outcome wording against the spec.

### Task 2: Add the QR scanner and Bike tab

**Files:** Create `QRScannerView.swift` and `BikeView.swift`; modify `ContentView.swift`, `RideScreenApp.swift`, and `Info.plist`.

- [x] Request camera access only from the explicit Scan button and provide a Settings route when access is denied.
- [x] Add scan review, editable bike name, save-and-join, saved bike retry, and removal interactions.
- [x] Show explicit unsupported-QR and Wi-Fi-configuration outcomes without claiming projection or dash connectivity.
- [x] Review all UI state transitions and camera teardown paths.

### Task 3: Document the slice and inspect integration

**Files:** Update `ios/README.md` and check all Xcode project references.

- [x] Document camera permission, iOS Wi-Fi approval, local credential storage, and the real-device Zontes validation still required.
- [x] Inspect the final diff for missing project references, accidental credential persistence, and behavior outside the spec.
- [x] Do not add or run tests or builds in this Windows environment; Xcode and Swift are unavailable. Record that limitation in the handoff.
