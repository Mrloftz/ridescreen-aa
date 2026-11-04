# iOS CarPlay-to-Dashboard Bridge Design

**Status:** Approved on 2026-11-04.

**Direction update (2026-11-05):** The user later selected a native CarPlay app. A separate initial `CPMapTemplate` scene has been added; it does not replace or satisfy this spec's independent video bridge to the Zontes dashboard. The scene currently provides a location-following map only. The iCarCast receiver framing remains an evidence-gated prerequisite before implementing video projection.

## Intent

Let an iPhone rider run real CarPlay navigation through the separate iCarCast receiver app and show
that receiver's video on a compatible Carbit / EasyConnect motorcycle dashboard through RideScreen's
PXC link. The first successful result is Apple Maps or another CarPlay navigation app visibly updating
on the user's Zontes 368E dashboard.

This is a sideloaded, experimental integration. It does not claim that RideScreen itself is a certified
CarPlay receiver or an Apple-approved head unit.

## Goals

- Consume the local iCarCast receiver's H.264 stream on the same iPhone.
- Establish the existing EasyConnect PXC control and media session from iOS.
- Deliver correctly framed H.264 access units to the dashboard before its roughly nine-second media
  timeout.
- Show clear, stage-specific diagnostics that a tester can copy after one hardware run.
- Keep receiver credentials, bike Wi-Fi credentials, video, and logs on the device.

## First-slice success criteria

1. The rider joins the saved bike Wi-Fi and starts iCarCast's **This iPhone** mode.
2. RideScreen detects a usable source at `127.0.0.1:8969`.
3. RideScreen completes the PXC probe, connect-back handshake, and media negotiation.
4. The Zontes 368E dashboard shows moving CarPlay navigation video for at least five minutes without a media
   timeout.
5. A failed run identifies its last completed stage: receiver discovery, source framing, bike probe,
   control handshake, media negotiation, or frame delivery.

## Non-goals for the video-bridge first slice

- Becoming a normal app inside CarPlay with `CPMapTemplate`.
- Implementing or distributing a CarPlay receiver.
- Reimplementing Apple's MFi CarPlay protocol.
- Audio, Siri microphone input, dashboard touch, handlebar controls, or automatic startup.
- Remote receiver devices or user-entered receiver hosts; the first slice is loopback-only.
- Wi-Fi Direct and phone-hosted-hotspot dashboard modes.
- Multiple dashboard profiles beyond the user's Zontes 368E access-point path.
- App Store distribution or a promise that Apple will approve this integration.

## Approaches considered

1. **External iCarCast receiver feeding RideScreen (selected).** This is the only short path that keeps
   real CarPlay rendering while allowing RideScreen to own the known PXC transport. It depends on a
   separate beta app and on a receiver interface that is not published as an SDK.
2. **Implement a CarPlay receiver in RideScreen.** This would remove the external dependency, but the
   receiver-side protocol and plug-in are part of Apple's MFi program. It is too large, legally
   constrained, and unnecessary for proving the dashboard path.
3. **Build RideScreen navigation with MapKit.** This is controllable with public APIs and may remain a
   fallback later, but it produces RideScreen navigation rather than the requested CarPlay experience.

## Evidence and assumptions

- iCarCast's public guide documents **This iPhone**, which runs CarPlay on the same iPhone while the
  phone is joined to Wi-Fi.
- Static inspection of the publicly distributed MOTO-HUB iOS 1.36.5 IPA found
  `CarPlayStreamSource`, `CarPlayH264Decoder`, Annex-B handling, and
  `http://localhost:8969/stream`. Its UI strings describe a receiver on the same phone and a web page
  on port 8969.
- The exact response headers, initial receiver negotiation, and access-unit framing are not publicly
  documented. They are deliberately treated as unknown until observed from a consenting test device.
- RideScreen's existing Android implementation and reverse-engineering notes define the target PXC
  behavior: probe the dashboard at port 10930, listen for connect-back on 10920/10921/10922, complete
  the control handshake, and answer media pulls with length-prefixed Annex-B access units.
- The repository already has field-confirmed Zontes 368E support shared with the 368G/368K family:
  QR model/channel `21334`, the `Cfdl16MotoPlayLandscapeProfile`, and a known `1024 x 425` panel.
  The user's photographed dashboard reports display firmware `AJ.V2.1.2.H3_20260624`.

## Architecture

### `CarPlayStreamSource`

A small source object owns the loopback receiver connection. It first checks the receiver's documented
web endpoint on port 8969, then opens `/stream`. Receiver parsing stays isolated behind an async access
unit sequence so no iCarCast-specific framing leaks into the PXC implementation.

The parser accepts only loopback traffic, caps headers and frame sizes, requires valid H.264 SPS/PPS
before publishing video, and stops on malformed or stalled input. The first hardware/research run logs
headers, message lengths, NAL types, dimensions, and timestamps but never logs video payloads or Wi-Fi
credentials.

If `/stream` proves to be a discovery or control endpoint rather than the raw video endpoint, this
component follows only the local address/port returned by it and records that finding in the protocol
fixture. No broad port scan is performed.

### `PXCLink`

Port the smallest reusable parts of the verified Android path to Swift:

- little-endian `CmdBaseHead` and `ReqBase` codecs;
- listeners on 10920, 10921, and 10922;
- probe to the dashboard's discovered or QR-derived address on 10930;
- Zontes 368 CLIENT_INFO/profile behavior, channel selection, serial-number check, APPSTATUS/time
  messages, heartbeat, and media requests, ported from the verified Android `21334` path;
- bounded H.264 queue and `[size little-endian][Annex-B access unit]` replies to data-next requests.

Network Framework (`NWListener` and `NWConnection`) is used for TCP. The link is active only after an
explicit rider action and is cancelled when the rider stops it or the source fails.

### `CarPlayVideoBridge`

The bridge inspects SPS dimensions and format before the first frame reaches the bike:

- If the source already matches the dashboard canvas and an accepted H.264 profile, forward access
  units without decoding.
- Otherwise decode with VideoToolbox, scale/aspect-fit into the negotiated canvas, and encode H.264
  Baseline level 3.1 with repeated SPS/PPS and regular keyframes.

The bridge owns a very small bounded queue. Fresh video wins over stale video. A source stall ends the
session with a diagnostic instead of leaving the dashboard on a frozen frame indefinitely.

### UI and diagnostics

The saved bike card gains **Project CarPlay**. The flow displays a short prerequisite sheet:

1. Install and configure iCarCast.
2. Join the bike Wi-Fi.
3. Start **This iPhone**, then return to RideScreen.
4. Tap **Connect to dashboard**.

The connection screen shows the current stage, frames received/sent, last-frame age, and a Stop button.
Failures include one corrective action and a copyable diagnostic report. The report redacts SSIDs,
passwords, bike identifiers, receiver tokens, and video bytes.

## Permissions and lifecycle

- Add `NSLocalNetworkUsageDescription` because RideScreen contacts and accepts connections from the
  dashboard on the local Wi-Fi network.
- Keep the existing Hotspot Configuration entitlement for joining the saved access point.
- This spec's receiver-to-dashboard bridge does not rely on CarPlay scenes. Native CarPlay UI and its restricted entitlement are tracked separately; neither substitutes for the video transport described here.
- The initial test keeps RideScreen in the foreground. Background continuation is a later slice because
  iOS may suspend ordinary networking, and a background-mode workaround must not misuse location or
  audio capabilities.

## Error handling

- Missing receiver: explain how to start iCarCast **This iPhone** and retry.
- Unexpected receiver response: save only a bounded, redacted framing summary for analysis.
- Local-network denial: link to app Settings.
- Bike probe/handshake timeout: close all listeners and preserve the receiver for a retry.
- Unsupported source geometry/profile: attempt the VideoToolbox conversion once; report encoder setup
  failure rather than sending incompatible frames.
- Source or bike disconnect: cancel the other side, clear queued frames, and return to a retryable
  stopped state.

## Verification

- Unit-test PXC codecs, receiver framing once known, Annex-B NAL parsing, size limits, and queue policy
  using captured metadata/fixtures with payloads removed or synthetic.
- Build and run in Xcode on a real iPhone; the current Windows host cannot compile the iOS target.
- First hardware checkpoint: receiver connection and H.264 metadata only.
- Second checkpoint: PXC handshake with a synthetic H.264 test pattern.
- Final checkpoint: iCarCast CarPlay stream for five minutes on the user's Zontes 368E dashboard, with a
  diagnostic export after success or failure.
- Checkpoint 1 is a hard gate: if bounded, redacted metadata does not establish the receiver framing,
  implementation pauses for a user-owned traffic/framing trace. Do not guess the framing or build the
  downstream bridge against an invented protocol.

## Known risks

- iCarCast has no public SDK or compatibility promise; its local endpoint can change between builds.
- Running a local receiver and the bike PXC link on the same Wi-Fi may expose lifecycle or routing
  behavior that static analysis cannot prove.
- App Store distribution is not assumed. Apple entitlements and review rules are separate from whether
  the local technical path works.
- The stream may require a negotiation detail that cannot be inferred from static inspection. In that
  case a packet/framing trace from the user's own device is required before product implementation.

## Codemagic IPA delivery

Add a repository-root `codemagic.yaml` with a native-iOS workflow. It builds the shared `RideScreen`
scheme on a Codemagic macOS worker, runs available non-device checks, and publishes the IPA plus Xcode
logs as downloadable artifacts. No Apple private key, certificate, profile, or API key is committed.

The default artifact is an unsigned development IPA that the rider can re-sign and install with
AltStore, SideStore, or Sideloadly. A second, optional signed workflow uses Codemagic's `ios_signing`
configuration when the rider connects a paid Apple Developer account and uploads/fetches a matching
certificate and development or ad-hoc provisioning profile. Codemagic then applies the profile with
`xcode-project use-profiles` and builds the IPA. TestFlight/App Store publication is outside this slice.

The unsigned path may lose capabilities when a sideloading tool re-signs it. In particular, if Hotspot
Configuration is unavailable, the checkpoint UI instructs the rider to join the dashboard Wi-Fi
manually in Settings; projection testing must not depend on programmatic Wi-Fi joining.

## Builder calls left open

- Exact Swift file boundaries and actor/queue ownership.
- The synthetic test pattern used for the PXC-only checkpoint.
- Concrete retry intervals and diagnostic wording, within the bounded and redacted behavior above.

