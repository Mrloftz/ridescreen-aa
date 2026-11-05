# RideScreen iOS Wi-Fi Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the bike Wi-Fi join flow clear for both entitlement-enabled builds and free Apple ID installs that must join manually.

**Architecture:** Keep the existing SwiftUI Bike screen, Keychain credential store, and `NEHotspotConfiguration` attempt. Present manual instructions as an explicit flow after automatic failure or when selected from a bike card; rider confirmation is transient and never represented as a verified SSID or bike connection.

**Tech Stack:** Swift 5, SwiftUI, UIKit, NetworkExtension.

**Spec:** `docs/superpowers/specs/2026-11-05-ios-wifi-flow-design.md`

## Global Constraints

- Preserve automatic join for builds whose signing profile includes Hotspot Configuration.
- Do not log or expose Wi-Fi passwords except for the explicit copy action.
- Do not claim the bike network or display service is connected based on a button tap or `apply` success.
- Do not implement Wi-Fi Direct, Carbit/EasyConn transport, video projection, or CarPlay navigation in this slice.
- Do not add or run tests; use static diff checks only. Device build and validation remain on Codemagic/iPhone.

## Review Focus

- Dismissing the automatic-failure alert must leave the manual steps visible and reachable.
- A rider-confirmed manual join must be visibly labeled unverified and must clear when the rider retries automatic joining.
- Credential copy must still read from the existing Keychain path and diagnostics must remain password-free.
- Existing accepted/already-associated messages must continue to avoid claiming the dash is connected.
- Removing a saved bike must not remove a network the rider added manually in iOS Settings.

---

### Task 1: Make manual join a clear Bike-screen flow

**Files:**
- Modify: `ios/RideScreen/BikeView.swift`
- Modify: `ios/RideScreen/Info.plist` (`CFBundleVersion` 3 → 4)

**Interfaces:**
- Reuse `BikeWiFiConnector.join`, `BikeStore.password(for:)`, `BikeNotice`, and `BikeManualWiFiInstructions`.
- Keep manual confirmation in view state only; do not persist it as verified connection data.

- [x] Keep the saved-bike card's manual instructions expanded after automatic setup fails; after dismissing the alert, show SSID, copy-password action, and Settings steps in the visible card.
- [x] Keep a manual-setup action on each saved bike card so free-account users can choose this path before trying automatic join.
- [x] Add a per-bike, view-only “I joined” action that displays “confirmed by you, not verified by RideScreen” and says this build does not yet connect to the bike display.
- [x] Clear that transient status when retrying automatic join or removing the bike.
- [x] Preserve the current accepted/already-associated semantics and do not add SSID detection that requires another entitlement.

### Task 2: Document the exact supported flow

**Files:**
- Modify: `ios/README.md`

- [x] Document QR scan → save bike → automatic join or manual Settings join → rider confirmation.
- [x] State that manual confirmation does not verify the current SSID or establish Carbit/EasyConn projection.
- [x] Clarify that this Wi-Fi flow does not change the experimental localhost receiver probe.

### Task 3: Review the diff without running tests

**Files:**
- Review: `ios/RideScreen/BikeView.swift`
- Review: `ios/README.md`

- [x] Run `git diff --check` and inspect the final diff for stale status, misleading connection claims, and password exposure.
- [x] Record that Codemagic build and physical iPhone validation are still required; do not claim the Wi-Fi link was verified here.
