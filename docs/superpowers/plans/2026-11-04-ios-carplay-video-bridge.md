# iOS CarPlay Video Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the synthetic source with iCarCast's real same-iPhone CarPlay H.264 stream and keep navigation video visible on the Zontes 368E for five minutes.

**Architecture:** The checkpoint-1 diagnostic first becomes a redacted protocol fixture; no stream parser is written until that fixture proves framing. `CarPlayStreamSource` converts the receiver stream into Annex-B access units. Compatible frames pass through; incompatible geometry/profile goes through a VideoToolbox decode-scale-encode bridge before entering the already-tested PXC link.

**Tech Stack:** Swift 5, Foundation `URLSession`, VideoToolbox, CoreVideo/CoreImage, iOS 16+.

**Spec:** `docs/superpowers/specs/2026-11-04-ios-carplay-bridge-design.md`

## Global Constraints

- This plan starts only after receiver checkpoint 1 and synthetic-PXC checkpoint 2 both pass.
- Do not guess receiver framing; checkpoint 1 metadata or a user-owned local trace must establish it first.
- Connect only to `127.0.0.1:8969`; accept no redirects or returned video endpoint outside loopback.
- Never persist or export video payloads; checked-in fixtures contain synthetic bytes or framing metadata only.
- Queue at most 3 access units; newest video wins; a 3-second source stall ends the session cleanly.
- Output to the dashboard remains H.264 Baseline level 3.1 at negotiated 1024x416.

## Review Focus

- Receiver changes framing/version: fail with `unsupported receiver response` and preserve a bounded metadata report.
- Receiver redirects to LAN/internet: reject it before opening the connection.
- SPS/PPS changes midstream: flush decoder/queue and require a fresh keyframe before forwarding.
- Source access unit exceeds 4 MiB or has invalid NAL lengths: stop without allocation explosion or partial forwarding.
- App goes inactive or source stalls: close PXC and receiver tasks once, clear queued frames, and leave Retry available.

---

### Task 1: Establish the receiver protocol fixture (hard gate)

**Files:**
- Create: `ios/Tests/Fixtures/iCarCastStreamMetadata.json`
- Modify: `docs/superpowers/specs/2026-11-04-ios-carplay-bridge-design.md`

**Interfaces:**
- Consumes: the redacted checkpoint-1 report from the receiver-probe plan.
- Produces: a versioned fixture describing HTTP status/headers, negotiation messages, length fields, byte order, and access-unit boundary evidence without video bytes.

- [ ] **Step 1: Review the exported receiver report**

Record iPhone/iOS/iCarCast versions and decide whether `/stream` is raw Annex-B, length-prefixed Annex-B, multipart, or a discovery response naming another loopback port.

- [ ] **Step 2: If framing is still ambiguous, capture a user-owned loopback/framing trace**

Collect only enough bytes/packet lengths to identify framing; redact tokens and replace any payload bytes with deterministic synthetic fixture bytes.

- [ ] **Step 3: Write the metadata fixture and document the confirmed protocol**

Expected: another engineer can implement frame extraction without seeing the original video payload.

- [ ] **Step 4: Stop if the protocol remains unknown**

Do not start Task 2. Report exactly which boundary or negotiation field is missing.

- [ ] **Step 5: Commit**

```bash
git add ios/Tests/Fixtures/iCarCastStreamMetadata.json docs/superpowers/specs/2026-11-04-ios-carplay-bridge-design.md
git commit -m "docs(ios): record local CarPlay stream framing"
```

### Task 2: Receiver stream parser and source

**Files:**
- Create: `ios/RideScreen/H264AnnexB.swift`
- Create: `ios/RideScreen/CarPlayStreamSource.swift`
- Create: `ios/Tests/CarPlayStreamSourceTests.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: confirmed fixture from Task 1 and `PXCVideoSource` from the PXC plan.
- Produces: `struct H264AccessUnit: Sendable, Equatable`, `struct H264Format: Sendable, Equatable`, `struct AnnexBParser`, and `actor CarPlayStreamSource: PXCVideoSource`.
- Produces: `CarPlayStreamSource.init(url: URL = http://127.0.0.1:8969/stream, session: URLSession = .shared)`.

- [ ] **Step 1: Write failing fixture-driven parser tests**

Assert arbitrary chunk boundaries, multiple units per chunk, SPS/PPS/IDR association, midstream SPS replacement, maximum sizes, end-of-stream behavior, loopback-only redirects, cancellation, and three-second stall.

- [ ] **Step 2: Run the harness and verify failure**

Expected: missing parser/source types.

- [ ] **Step 3: Implement the confirmed framing only**

Keep receiver negotiation inside `CarPlayStreamSource`; publish complete Annex-B access units through `nextAccessUnit(deadline:)`; never expose raw URLSession callbacks to PXC.

- [ ] **Step 4: Run all pure harnesses**

Expected: all exit 0.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/H264AnnexB.swift ios/RideScreen/CarPlayStreamSource.swift ios/Tests/CarPlayStreamSourceTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "feat(ios): consume local CarPlay h264 stream"
```

### Task 3: Passthrough decision and bounded queue

**Files:**
- Create: `ios/RideScreen/CarPlayVideoBridge.swift`
- Create: `ios/Tests/CarPlayVideoBridgeTests.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `H264AccessUnit`, `H264Format`, `CarPlayStreamSource`, and `PXCVideoSource`.
- Produces: `actor CarPlayVideoBridge: PXCVideoSource`, `enum VideoBridgeMode: Equatable { case passthrough, transcode }`, and `static func mode(source: H264Format, target: H264Format) -> VideoBridgeMode`.

- [ ] **Step 1: Write failing decision/queue tests**

Passthrough only when dimensions, Baseline-compatible profile/level, Annex-B parameter sets, and no frame reordering match the target; every mismatch chooses transcode. Queue depth is 3, drops oldest non-keyframes first, flushes on format change, and emits nothing until SPS/PPS plus IDR are available.

- [ ] **Step 2: Run and verify failure**

Expected: missing bridge types.

- [ ] **Step 3: Implement passthrough and queue policy**

Do not add decoding yet; `.transcode` must return a clear `transcoder unavailable` error until Task 4.

- [ ] **Step 4: Run all harnesses**

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/CarPlayVideoBridge.swift ios/Tests/CarPlayVideoBridgeTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "feat(ios): bridge compatible CarPlay frames"
```

### Task 4: VideoToolbox decode-scale-encode fallback

**Files:**
- Create: `ios/RideScreen/H264Transcoder.swift`
- Create: `ios/Tests/H264TranscoderTests.swift`
- Modify: `ios/RideScreen/CarPlayVideoBridge.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 2 access units/formats and the target format from the PXC session.
- Produces: `actor H264Transcoder` with `configure(source: H264Format, targetWidth: Int, targetHeight: Int) async throws`, `append(_ unit: H264AccessUnit) async throws -> [H264AccessUnit]`, `requestKeyFrame()`, and `stop()`.

- [ ] **Step 1: Add failing device-capable transcoder checks**

Feed a generated non-1024x416 H.264 fixture; assert output is 1024x416, Baseline 3.1, Annex-B, aspect-fit on black, no B-frames, SPS/PPS before IDR, 2.5 Mbps/30 fps/one-second keyframes, and clean recovery after a source SPS change.

- [ ] **Step 2: Implement VideoToolbox decode/scale/encode**

Use `VTDecompressionSession`, `VTPixelTransferSession` or CoreImage for aspect-fit, and `VTCompressionSession`; serialize callbacks into the actor and release all sessions/pixel buffers on stop or reconfigure.

- [ ] **Step 3: Wire transcode mode into `CarPlayVideoBridge`**

Passthrough remains allocation-light; transcode activates only after format inspection proves it necessary.

- [ ] **Step 4: Run all harnesses and Codemagic IPA build**

Expected: all host checks pass; device-only checks compile and the unsigned IPA is produced.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/H264Transcoder.swift ios/RideScreen/CarPlayVideoBridge.swift ios/Tests/H264TranscoderTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "feat(ios): transcode CarPlay video for bike display"
```

### Task 5: End-to-end CarPlay projection session

**Files:**
- Modify: `ios/RideScreen/CarPlayProjectionView.swift`
- Modify: `ios/RideScreen/PXCLink.swift`
- Modify: `ios/README.md`
- Test: `ios/Tests/ProjectionSessionTests.swift`

**Interfaces:**
- Consumes: `PXCLink`, `CarPlayStreamSource`, `CarPlayVideoBridge`, and `ProjectionDiagnostics`.
- Produces: `@MainActor final class CarPlayProjectionModel: ObservableObject` with `start(bike:)`, `stop()`, retryable state, live receiver/bike frame counters, last-frame age, and `exportDiagnostic()`.

- [ ] **Step 1: Write failing orchestration tests**

Assert receiver starts before PXC probe; receiver failure skips PXC; PXC failure stops receiver/bridge; source stall stops PXC; app inactive stops all components; repeated Stop is idempotent; Retry creates fresh components and an empty queue.

- [ ] **Step 2: Implement the orchestration model**

Replace **Test dashboard link** with **Connect to dashboard** while retaining the synthetic test action under diagnostics. Show explicit stages and one correction per failure.

- [ ] **Step 3: Update usage documentation**

Document iCarCast **This iPhone**, manual Zontes Wi-Fi joining, returning to RideScreen, keeping the phone unlocked/foreground, stopping, and sharing diagnostics.

- [ ] **Step 4: Run all harnesses and Codemagic `ios-unsigned`**

Expected: IPA builds and installs after re-signing.

- [ ] **Step 5: Five-minute Zontes 368E hardware checkpoint**

Show live Apple Maps/CarPlay navigation for five minutes. Verify receiver frames, bike pulls, sent access units, last-frame age under three seconds, and no media timeout. Export a redacted report whether it passes or fails.

- [ ] **Step 6: Commit**

```bash
git add ios/RideScreen/CarPlayProjectionView.swift ios/RideScreen/PXCLink.swift ios/README.md ios/Tests/ProjectionSessionTests.swift
git commit -m "feat(ios): project CarPlay to Zontes dashboard"
```

