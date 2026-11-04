# iOS Android Visual Parity Implementation Plan

> **For agentic workers:** Implement inline using the existing isolated worktree and Codemagic iOS workflow.

**Goal:** Make the existing iOS app screens share Android's matte-green, gold, Archivo, and card visual identity.

**Architecture:** Add a shared SwiftUI palette, typography, and card/button styles. Apply those styles to the existing Ride, Trips, Garage, bike-review, and Project CarPlay views without changing data or navigation behavior.

**Tech Stack:** Swift 5, SwiftUI, existing Xcode project, existing Android Archivo font assets.

**Spec:** `docs/superpowers/specs/2026-11-04-ios-android-visual-parity-design.md`

## Global Constraints

- Preserve iOS deployment target 16.0 and the existing SwiftUI app structure.
- Add no third-party dependencies.
- Keep iOS system permission and Wi-Fi confirmation behavior intact.
- Do not imply that the visual pass implements PXC or dashboard video projection.
- Use Android palette values verbatim from `app/src/main/res/values/colors.xml`.

## Review Focus

- Dynamic Type: card labels and long SSIDs remain readable and do not clip.
- Dark-mode presentation: every tab and modal uses the same background and text contrast.
- Long bike names and SSIDs: content wraps or truncates without hiding essential actions.
- Status/error states: busy, failed, and ready colors remain distinguishable and accessible.
- Modal navigation: QR review and diagnostic sharing remain dismissible and retain their current actions.

---

### Task 1: Shared visual tokens and ride/history screens

**Files:**
- Create: `ios/RideScreen/RideScreenTheme.swift`
- Create: `ios/RideScreen/Fonts/ArchivoBlack-Regular.ttf`, `OFL-Archivo.txt`
- Modify: `ios/RideScreen/ContentView.swift`
- Modify: `ios/RideScreen/TripDetailView.swift`
- Modify: `ios/RideScreen/Info.plist`
- Modify: `ios/RideScreen.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `RideScreenTheme` palette, `RideScreenCard` styling, and Archivo font helpers for all SwiftUI screens.
- Consumes the Android colors and font files already in `app/src/main/res`.

- [x] Add the shared palette and reusable card/primary-action styles using the exact spec values.
- [x] Register the verified Archivo Black font and its license in `UIAppFonts` and Xcode resources.
- [x] Apply the shared visual style to the tab bar, Ride, Trips, and trip detail screens.
- [x] Keep navigation, route rendering, and ride controls behavior unchanged.

### Task 2: Garage and bike pairing flow

**Files:**
- Modify: `ios/RideScreen/BikeView.swift`
- Modify: `ios/RideScreen/RideScreen.xcodeproj/project.pbxproj` only if resource membership needs correction.

**Interfaces:**
- Consumes existing `BikeStore`, `BikeWiFiConnector`, and `BikePairing` APIs.
- Produces Android-styled Garage cards, scan action, and bike-review presentation.

- [x] Replace generic grouped list/form surfaces with the shared background, header, cards, and gold action buttons.
- [x] Keep saved bike removal, QR parsing, Keychain storage, and Wi-Fi feedback semantics intact.
- [x] Give the bike name, SSID, status, and primary action a clear hierarchy on iPhone-sized screens.

### Task 3: Project CarPlay checkpoint screen

**Files:**
- Modify: `ios/RideScreen/CarPlayProjectionView.swift`

**Interfaces:**
- Consumes the existing `ProjectionProbeModel` and `Bike` data.
- Produces a styled prerequisite checklist, receiver status card, and diagnostic actions.

- [x] Apply the same colors, typography, card borders, and action sizing as Garage.
- [x] Preserve probe, retry, cancel, and diagnostic export behavior.
- [x] Keep failed and busy status colors semantically distinct.

### Task 4: Build handoff

- [x] Run `git diff --check` and review project resource references.
- [x] Commit the visual pass on `feat/ios-carplay-bridge`.
- [x] Push so the user can build the updated IPA with `ios-unsigned` in Codemagic.

**Verification limitation:** The current Windows host has no Xcode; the user-facing Xcode build remains a Codemagic gate.
