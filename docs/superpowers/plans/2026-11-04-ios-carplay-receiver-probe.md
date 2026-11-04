# iOS CarPlay Receiver Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an installable Codemagic IPA that probes the same-iPhone iCarCast endpoint, records bounded redacted stream metadata, and lets the rider export one diagnostic report.

**Architecture:** Keep all receiver-specific behavior behind a loopback-only `CarPlayReceiverProbe`. A small diagnostics store exposes stage events to SwiftUI and exports redacted text; no video payload is persisted. Codemagic builds an unsigned IPA for AltStore/SideStore and offers a separate signed workflow when signing identities exist.

**Tech Stack:** Swift 5, SwiftUI, Foundation `URLSession`, iOS 16+, Xcode command-line tools, Codemagic YAML.

**Spec:** `docs/superpowers/specs/2026-11-04-ios-carplay-bridge-design.md`

## Global Constraints

- Probe only `http://127.0.0.1:8969/stream`; no configurable host or port in this slice.
- Read at most 64 KiB or 3 seconds, whichever comes first; never persist response bodies or video bytes.
- Diagnostic output must redact SSIDs, Wi-Fi passwords, MAC/HUID values, URL credentials/query values, and receiver tokens.
- Keep the existing iOS 16.0 deployment target and Swift 5 mode; add no third-party package.
- The default Codemagic artifact is unsigned and assumes manual bike Wi-Fi joining after free-Apple-ID re-signing.

## Review Focus

- Receiver is absent or refuses localhost: the UI must remain retryable and explain how to start iCarCast **This iPhone**.
- `/stream` never finishes: the probe must stop at 3 seconds or 64 KiB and release the URLSession task.
- Response contains credentials or identifiers: the exported report must redact values while retaining field names and lengths.
- Response begins mid-NAL or is not H.264: metadata must say `unknown` rather than logging bytes or crashing.
- Codemagic has no Apple signing identities: the unsigned workflow must still produce an IPA and build log.

---

### Task 1: Pure diagnostic and stream-summary core

**Files:**
- Create: `ios/RideScreen/ProjectionDiagnostics.swift`
- Create: `ios/RideScreen/ReceiverStreamSummary.swift`
- Create: `ios/Tests/ReceiverProbeCoreTests.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `enum ProjectionStage: String, Codable`, `struct ProjectionEvent: Codable, Equatable`, `actor ProjectionDiagnostics`, and `struct ReceiverStreamSummary: Equatable`.
- Produces: `DiagnosticRedactor.redact(_ text: String) -> String` and `ReceiverStreamSummary.inspect(_ data: Data, headers: [String: String], statusCode: Int?) -> ReceiverStreamSummary`.

- [ ] **Step 1: Write the failing assertion-based core tests**

Cover: event cap at 500 oldest-dropped entries; redaction of `ssid`, `pwd/password`, `mac`, `huid`, `token`, and URL query values; preservation of harmless stage text; Annex-B prefixes `00 00 01` and `00 00 00 01` summarized by NAL type/count without payload; random/truncated bytes summarized as `unknown`; byte count and HTTP metadata preserved.

- [ ] **Step 2: Run the core test harness and verify it fails**

Run on a macOS/Xcode host:

```bash
xcrun swiftc ios/RideScreen/ProjectionDiagnostics.swift ios/RideScreen/ReceiverStreamSummary.swift ios/Tests/ReceiverProbeCoreTests.swift -o /tmp/ridescreen-probe-tests && /tmp/ridescreen-probe-tests
```

Expected: compile failure because the production types do not exist.

- [ ] **Step 3: Implement the pure types**

`ProjectionDiagnostics` must expose `record(stage: ProjectionStage, message: String)`, `events() -> [ProjectionEvent]`, `clear()`, and `exportText(appVersion: String, device: String) -> String`. `ReceiverStreamSummary` stores only status, normalized content type, bytes observed, detected framing, and NAL type counts.

- [ ] **Step 4: Run the core test harness**

Expected: exits 0 and prints `ReceiverProbeCoreTests passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/ProjectionDiagnostics.swift ios/RideScreen/ReceiverStreamSummary.swift ios/Tests/ReceiverProbeCoreTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "test(ios): add projection diagnostic core"
```

### Task 2: Bounded loopback receiver probe

**Files:**
- Create: `ios/RideScreen/CarPlayReceiverProbe.swift`
- Create: `ios/Tests/CarPlayReceiverProbeTests.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ReceiverStreamSummary.inspect` and `ProjectionDiagnostics.record` from Task 1.
- Produces: `struct CarPlayReceiverProbe` with `static let streamURL`, `init(streamURL: URL = streamURL, byteLimit: Int = 65_536, timeout: Duration = .seconds(3))`, and `func run(session: URLSession = .shared) async throws -> ReceiverStreamSummary`.
- Produces: `enum ReceiverProbeError: LocalizedError, Equatable` with `.notRunning`, `.invalidResponse`, `.timedOut`, and `.cancelled`.

- [ ] **Step 1: Write URLProtocol-backed failing tests**

Cover: only `127.0.0.1:8969/stream` is requested; HTTP error maps to `.notRunning`; a chunked response stops at 64 KiB; a non-ending response stops at 3 seconds using an injected clock/deadline; cancellation cancels the underlying task; returned headers/body go only through `ReceiverStreamSummary`.

- [ ] **Step 2: Run both test harnesses and verify the new one fails**

Use `xcrun swiftc` with Task 1 sources plus `CarPlayReceiverProbe.swift` and `CarPlayReceiverProbeTests.swift`. Expected: compile failure for the missing probe.

- [ ] **Step 3: Implement `CarPlayReceiverProbe`**

Use an ephemeral `URLSessionConfiguration` with no cache or cookies. Stream bytes asynchronously, enforce the byte/deadline bounds, cancel on every terminal path, and return metadata only.

- [ ] **Step 4: Run both core test harnesses**

Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/CarPlayReceiverProbe.swift ios/Tests/CarPlayReceiverProbeTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "feat(ios): probe local CarPlay receiver"
```

### Task 3: Projection checkpoint UI and export

**Files:**
- Create: `ios/RideScreen/CarPlayProjectionView.swift`
- Modify: `ios/RideScreen/BikeView.swift`
- Modify: `ios/RideScreen/RideScreenApp.swift`
- Modify: `ios/RideScreen/Info.plist`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CarPlayReceiverProbe.run`, `ProjectionDiagnostics`, and existing `Bike` rows.
- Produces: `@MainActor final class ProjectionProbeModel: ObservableObject` with `state`, `summary`, `startProbe()`, `cancel()`, and `exportText()`.
- Produces: `CarPlayProjectionView(bike: Bike)` presented from a saved bike's **Project CarPlay** button.

- [ ] **Step 1: Add a failing model-state harness**

Use an injected probe closure to assert `idle -> probing -> ready`, receiver absence returns to retryable `failed`, cancellation returns to `idle`, and exported text contains metadata but no sampled bytes.

- [ ] **Step 2: Run the model harness and verify failure**

Expected: compile failure because `ProjectionProbeModel` is absent.

- [ ] **Step 3: Implement the model and view**

The view shows the four prerequisites from the spec, **Probe iCarCast**, current stage, bounded summary, **Share diagnostic**, Retry, and Cancel. Add `NSLocalNetworkUsageDescription` and `NSAppTransportSecurity.NSAllowsLocalNetworking = true`; do not add a CarPlay scene or entitlement.

- [ ] **Step 4: Add the saved-bike entry point**

Place **Project CarPlay** beside **Join Wi-Fi** without changing bike deletion or QR behavior. Inject one app-wide `ProjectionDiagnostics` object from `RideScreenApp`.

- [ ] **Step 5: Run the pure harnesses and an unsigned simulator build**

```bash
xcodebuild -project ios/RideScreen.xcodeproj -target RideScreen -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/RideScreen/CarPlayProjectionView.swift ios/RideScreen/BikeView.swift ios/RideScreen/RideScreenApp.swift ios/RideScreen/Info.plist ios/RideScreen.xcodeproj/project.pbxproj ios/Tests
git commit -m "feat(ios): add CarPlay receiver checkpoint"
```

### Task 4: Codemagic unsigned and optional signed IPA workflows

**Files:**
- Create: `codemagic.yaml`
- Create: `ios/RideScreen.xcodeproj/xcshareddata/xcschemes/RideScreen.xcscheme`
- Modify: `ios/README.md`

**Interfaces:**
- Consumes: the `RideScreen` Xcode project and all core harnesses.
- Produces: Codemagic workflows `ios-unsigned` and `ios-signed`, artifact `build/ios/ipa/RideScreen-unsigned.ipa`, and `/tmp/xcodebuild_logs/*.log`.

- [ ] **Step 1: Add the shared scheme and validate Xcode sees it**

Run `xcodebuild -project ios/RideScreen.xcodeproj -list`; expected scheme: `RideScreen`.

- [ ] **Step 2: Add `ios-unsigned`**

Run all assertion harnesses, build Release for `iphoneos` with `CODE_SIGNING_ALLOWED=NO`, copy `RideScreen.app` into `Payload/`, zip it as `RideScreen-unsigned.ipa`, and publish the IPA plus Xcode logs.

- [ ] **Step 3: Add opt-in `ios-signed`**

Configure `ios_signing` for bundle identifier `dev.zanderp.opencfmoto.ios`, run `xcode-project use-profiles`, then `xcode-project build-ipa --project ios/RideScreen.xcodeproj --scheme RideScreen`. Do not add certificate/profile values or App Store Connect secrets to the repository.

- [ ] **Step 4: Document installation and diagnostics**

Explain unsigned IPA installation via AltStore Classic/SideStore/Sideloadly, the free-ID seven-day refresh, manual Wi-Fi joining when Hotspot Configuration is stripped, and how to send the exported receiver report.

- [ ] **Step 5: Trigger `ios-unsigned` in Codemagic**

Expected: all harnesses pass, `RideScreen-unsigned.ipa` downloads, and the build log contains no signing secret.

- [ ] **Step 6: Install the IPA and run checkpoint 1**

On the test iPhone: start iCarCast **This iPhone**, return to RideScreen, open the saved Zontes 368E, tap **Project CarPlay**, run the probe, and export the diagnostic. Expected: HTTP status/headers, bounded byte count, and framing/NAL summary with no payload or credentials.

- [ ] **Step 7: Commit**

```bash
git add codemagic.yaml ios/RideScreen.xcodeproj/xcshareddata/xcschemes/RideScreen.xcscheme ios/README.md
git commit -m "ci(ios): build diagnostic ipa with Codemagic"
```

