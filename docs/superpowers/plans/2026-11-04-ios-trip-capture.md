# iOS Trip Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native iOS app that records GPS rides, stores them locally, and lists saved rides.

**Architecture:** A SwiftUI app owns one Core Location recorder and a local Codable JSON store. Recording can continue in the background after the rider starts it in the foreground; checkpoints support recovery after process termination.

**Tech Stack:** Swift 5, SwiftUI, Core Location, Foundation, Xcode project.

**Spec:** `docs/superpowers/specs/2026-11-04-ios-trip-capture-design.md`

## Global Constraints

- Minimum deployment target: iOS 16.0.
- Use only SwiftUI, Core Location, and Foundation; add no third-party packages.
- Keep ride and route data on the device in Application Support JSON.
- Use When In Use authorization and an explicit user start action.
- If iOS grants reduced accuracy, request temporary full accuracy with a declared purpose string; explain the Settings path if declined.
- Background recording requires `UIBackgroundModes`=`location` and `allowsBackgroundLocationUpdates` enabled only during recording.
- Match Android thresholds: 35 m accuracy, 75 m/s jump limit, 0.8 m/s motion, 300 m and 30 seconds minimum ride, 10 minute gap bridge, 3 minute idle split, 30 second checkpoint.
- Do not add or run tests in this slice; build/device validation needs macOS with Xcode, unavailable on the current host.

## Review Focus

- Denied/restricted or reduced-accuracy location access must leave recording stopped and explain the Settings path.
- Stale, inaccurate, or implausible GPS fixes must not inflate distance.
- Stopping or process termination must not silently erase a meaningful ride; checkpoints recover only once.
- Short or stationary sessions must not appear as completed rides.
- A malformed or unwritable archive must be reported without overwriting the user's existing trip file.

---

### Task 1: Create the iOS application target

**Files:**
- Create: `ios/RideScreen.xcodeproj/project.pbxproj`
- Create: `ios/RideScreen/Info.plist`
- Create: `ios/README.md`
- Create: `ios/RideScreen/RideScreenApp.swift`

**Interfaces:**
- Produces: iOS 16 application target `RideScreen`, bundle ID `dev.zanderp.opencfmoto.ios`, SwiftUI app entry point, and the location background capability/configuration.

- [ ] Add an Xcode project with one iPhone/iPad app target, iOS 16 deployment target, Swift 5 language mode, and automatic signing.
- [ ] Add an Info.plist with the location usage string and `UIBackgroundModes` location entry.
- [ ] Add the SwiftUI `@main` entry point and a short build note that names the macOS/Xcode requirement.
- [ ] Review project references and plist settings for consistency; do not run tests or claim a build on this host.

### Task 2: Add local trip data and safe persistence

**Files:**
- Create: `ios/RideScreen/Trip.swift`
- Create: `ios/RideScreen/TripStore.swift`

**Interfaces:**
- Produces: Codable `TrackPoint`, `RideDraft`, and `Ride` models; a main-actor `TripStore` exposing saved rides, active checkpoint state, `checkpoint(_:)`, `finish(_:)`, and checkpoint recovery.

- [ ] Define Codable point, draft, ride, and archive models with UUID ride identity and timestamps.
- [ ] Load and save the archive at `Application Support/RideScreen/trips.json` using atomic writes.
- [ ] Preserve and report a decode/write error instead of replacing a damaged archive with an empty one.
- [ ] Recover a qualifying draft once as a finished ride and clear the active checkpoint in the same archive update.
- [ ] Review save ordering so a failed disk write cannot discard the last valid in-memory archive.

### Task 3: Implement GPS recording and filtering

**Files:**
- Create: `ios/RideScreen/TripRecorder.swift`

**Interfaces:**
- Consumes: `TrackPoint`, `RideDraft`, `Ride`, and `TripStore` from Task 2.
- Produces: observable recorder state and explicit `startRecording()` / `stopRecording()` actions for the UI.

- [ ] Configure Core Location for automotive navigation and request When In Use permission only after Start.
- [ ] Request temporary full accuracy when permission is reduced; provide the ride-specific purpose string and Settings guidance if declined.
- [ ] Start updates in the foreground and enable background updates only for an active ride.
- [ ] Reject stale fixes, accuracy above 35 m, and point jumps faster than 75 m/s.
- [ ] Compute live speed, distance, moving time, and maximum speed with the spec's motion and gap rules.
- [ ] Split a ride after 3 minutes parked, checkpoint every 30 seconds, and save only rides meeting all three Android thresholds.
- [ ] Stop Core Location and clear the active checkpoint on stop, including when a ride is too short to save.
- [ ] Review permission-denied, location failure, checkpoint, and stop paths in source.

### Task 4: Add the ride and trip-history screens

**Files:**
- Create: `ios/RideScreen/ContentView.swift`
- Modify: `ios/RideScreen/RideScreenApp.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TripRecorder` published state and `TripStore` saved rides from Task 3.
- Produces: Ride and Trips tabs with the live metrics, permission guidance, recording control, and locally saved ride summaries.

- [ ] Show current speed, distance, moving time, recording status, and Start/Stop control in the Ride tab.
- [ ] Explain denied location permission and provide a link to iOS Settings.
- [ ] List saved rides newest first with date, distance, moving time, and max speed.
- [ ] Surface persistence errors without hiding already saved rides.
- [ ] Review the final diff and record that a macOS Xcode build and real-device GPS/background session remain required.
