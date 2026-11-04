# iOS Zontes 368E PXC Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the iPhone app to the Zontes 368E EasyConn service and keep a generated H.264 test pattern visible on its 1024x425 dashboard.

**Architecture:** Pure Swift codecs and state machines reproduce the repository's verified Android model/channel `21334` behavior. A Network-framework link listens for the dashboard's three connect-back sockets and probes the EasyConn endpoint only after all listeners are ready. A VideoToolbox encoder supplies a synthetic 1024x416 Baseline stream, isolating PXC validation from iCarCast.

**Tech Stack:** Swift 5, Foundation, Network framework, Security framework, VideoToolbox, CoreVideo, iOS 16+.

**Spec:** `docs/superpowers/specs/2026-11-04-ios-carplay-bridge-design.md`

## Global Constraints

- Support only the Zontes 368 family profile: QR/client channel `21334`, landscape panel `1024x425`, negotiated coded height rounded to `416`.
- Listen on TCP 10920/10921/10922 before probing `_EasyConn._tcp` or fallback `192.168.0.1:10930`.
- Cap every control/media payload at 1 MiB and every video access unit at 4 MiB; malformed lengths close that connection.
- Encode H.264 Baseline level 3.1, 30 fps, 2.5 Mbps, one-second keyframe interval, SPS/PPS repeated with keyframes.
- No touch, audio, background operation, Wi-Fi Direct, remote receivers, or automatic reconnect in this checkpoint.

## Review Focus

- One of 10920/10921/10922 is already occupied: stop before probing and report the exact port.
- Dashboard sends fragmented/coalesced TCP frames: incremental codecs must emit exactly complete frames and retain partial bytes.
- Dashboard requests 1024x425: reply and encoder must consistently use 1024x416.
- Unknown 368 control notification: acknowledge with `cmd + 1` without echoing its payload.
- Video source stalls before nine seconds: session must report `source stalled` and close instead of spinning or sending an invalid length.

---

### Task 1: PXC wire codecs

**Files:**
- Create: `ios/RideScreen/PXCCodec.swift`
- Create: `ios/Tests/PXCCodecTests.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `struct PXCCmdFrame: Equatable`, `struct PXCReqFrame: Equatable`, `struct PXCCmdDecoder`, `struct PXCReqDecoder`.
- Produces: `PXCCmdFrame.encoded() throws -> Data`, `PXCReqFrame.encoded() throws -> Data`, and `PXCVideoWire.wrap(accessUnit: Data) throws -> Data`.

- [ ] **Step 1: Write failing known-vector and fragmentation tests**

Assert the 16-byte command header fields (`cmd`, total length, XOR magic, reserved zero), 8-byte request header (`Int16 cmd`, `UInt16 length`, `Int32 token` little-endian), raw video `[UInt32 length][Annex-B AU]`, byte-by-byte fragmentation, multiple frames per append, invalid magic, underflow, and size-cap rejection.

- [ ] **Step 2: Run the Swift harness and verify failure**

Expected: missing codec types.

- [ ] **Step 3: Implement the incremental codecs**

Expose `mutating func append(_ data: Data) throws -> [Frame]`; never allocate from an unvalidated wire length.

- [ ] **Step 4: Run all pure harnesses**

Expected: codec and receiver-probe harnesses exit 0.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/PXCCodec.swift ios/Tests/PXCCodecTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "test(ios): add pxc wire codecs"
```

### Task 2: Zontes 368 control and media state machines

**Files:**
- Create: `ios/RideScreen/PXCSessionKeys.swift`
- Create: `ios/RideScreen/Zontes368Session.swift`
- Create: `ios/Tests/Zontes368SessionTests.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PXCCmdFrame` and `PXCReqFrame` from Task 1.
- Produces: `final class PXCSessionKeys` with `publicKeyBase64` and `signHUID(_ huid: String) throws -> String` using a session-scoped 1024-bit RSA key.
- Produces: `struct Zontes368ControlSession` with `mutating func receive(_ frame: PXCCmdFrame, on channel: PXCChannel) throws -> [PXCAction]`.
- Produces: `struct Zontes368MediaSession` with `mutating func receive(_ frame: PXCReqFrame) throws -> [PXCMediaAction]`.

- [ ] **Step 1: Write failing state-machine tests**

Cover CAR_CTRL/CAR_DATA selection ACKs; CLIENT_INFO reply fields and raw RSA signature verification; QUERY_SPEED and heartbeat ACKs; CHECK_SN ACK plus `0x201c0` on CAR_DATA; one-second `0x20020` APPSTATUS for channel `21334`; query-time reply; unknown notification `cmd+1`; config-capture 1024x425 -> 1024x416; version 3/1; heartbeat, extend state 0, data-start, and data-next actions.

- [ ] **Step 2: Run the harness and verify failure**

Expected: missing session types.

- [ ] **Step 3: Implement session keys and pure responders**

Use Security framework `SecKey` APIs and raw RSA signing compatible with the verified Android private-key operation. Build client info with the same protocol/package/support fields as the Android 368 path while reporting Apple device metadata only in non-gating fields.

- [ ] **Step 4: Run all pure harnesses**

Expected: all exit 0.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/PXCSessionKeys.swift ios/RideScreen/Zontes368Session.swift ios/Tests/Zontes368SessionTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "feat(ios): add Zontes 368 pxc session"
```

### Task 3: Network-framework EasyConn link

**Files:**
- Create: `ios/RideScreen/PXCLink.swift`
- Create: `ios/Tests/PXCLinkStateTests.swift`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 codecs, Task 2 session actions, and `ProjectionDiagnostics` from the receiver-probe plan.
- Produces: `actor PXCLink` with `start(videoSource: PXCVideoSource) async throws`, `stop() async`, and `status() -> PXCLinkStatus`.
- Produces: `protocol PXCVideoSource: Sendable` with `start(width: Int, height: Int) async throws`, `requestKeyFrame() async`, `nextAccessUnit(deadline: ContinuousClock.Instant) async throws -> Data`, and `stop() async`.

- [ ] **Step 1: Write failing injected-transport state tests**

Assert listeners become ready in order 10920/10921/10922 before probe; any bind failure cancels all listeners and skips probe; Bonjour result wins over `192.168.0.1:10930`; accepted probe starts connect-back handling; each port selects the correct decoder; stop cancels every connection/source exactly once.

- [ ] **Step 2: Run the harness and verify failure**

Expected: missing link and transport abstractions.

- [ ] **Step 3: Implement `PXCLink` with injectable transport factories**

Use `NWListener`/`NWConnection`, keep socket callbacks serialized inside the actor, apply action outputs to the correct channel, and record every stage without payloads. Probe JSON is `{"phoneType":"Android","packageName":"com.cfmoto.cfmotointernational"}`.

- [ ] **Step 4: Run pure harnesses and unsigned simulator build**

Expected: all pass and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/RideScreen/PXCLink.swift ios/Tests/PXCLinkStateTests.swift ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "feat(ios): connect to EasyConn pxc service"
```

### Task 4: Synthetic H.264 source and checkpoint UI

**Files:**
- Create: `ios/RideScreen/SyntheticVideoSource.swift`
- Modify: `ios/RideScreen/CarPlayProjectionView.swift`
- Modify: `ios/RideScreen/Info.plist`
- Modify: `ios/README.md`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PXCVideoSource`, `PXCLink`, and `ProjectionDiagnostics`.
- Produces: `actor SyntheticVideoSource: PXCVideoSource` using `VTCompressionSession`.

- [ ] **Step 1: Add a failing encoder configuration/self-check harness**

Assert requested dimensions are 1024x416, Baseline 3.1/no frame reordering, 30 fps, 2.5 Mbps, one-second keyframes, bounded queue depth 3, and emitted keyframes are Annex-B with SPS/PPS before IDR.

- [ ] **Step 2: Implement `SyntheticVideoSource`**

Render a high-contrast frame containing `RideScreen`, a moving bar, frame number, and timestamp into a `CVPixelBuffer`; convert VideoToolbox AVCC output to Annex-B; latest frame wins when the queue is full.

- [ ] **Step 3: Add **Test dashboard link** to the projection checkpoint**

Require the rider to confirm manual Wi-Fi connection, start `PXCLink` with `SyntheticVideoSource`, show negotiated size/frames received/frames sent/last-frame age, and expose Stop plus diagnostic export.

- [ ] **Step 4: Run all harnesses and Codemagic `ios-unsigned`**

Expected: IPA artifact builds with all tests passing.

- [ ] **Step 5: Hardware checkpoint on Zontes 368E**

Install the IPA, join the dashboard AP, keep the projection QR/page open, start the test link, and leave it for five minutes. Expected: moving test pattern on the 1024x425 panel and diagnostic stages through `frame delivery`; otherwise export the report and stop this plan at the failing stage.

- [ ] **Step 6: Commit**

```bash
git add ios/RideScreen/SyntheticVideoSource.swift ios/RideScreen/CarPlayProjectionView.swift ios/RideScreen/Info.plist ios/README.md ios/RideScreen.xcodeproj/project.pbxproj
git commit -m "feat(ios): stream test video to Zontes 368"
```

