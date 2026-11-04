# iOS Bike Pairing Design

**Status:** First bike-pairing slice, based on the previously agreed iPhone-first scope.

## Intent

Let a rider add a Zontes 125X/125V by scanning its Carbit/EasyConnect pairing QR, save the Wi-Fi access-point details locally, and ask iOS to join that network with the rider's approval.

## Goals

- Add a Bike tab with a camera QR scanner and a list of saved bikes.
- Parse Carbit QR query fields for SSID, password, display name, model ID, MAC, and action bits.
- Accept a QR only when it includes usable Wi-Fi AP credentials and the AP action bit.
- Store bike metadata in Application Support and the Wi-Fi password in Keychain.
- Use Apple's hotspot configuration API and explain that an accepted Wi-Fi request does not prove the dash service is connected.

## Non-goals

- Wi-Fi Direct/P2P, phone-hosted hotspot QR codes, manual Wi-Fi entry, photo scanning, dash protocol communication, Android data import, projection, and CarPlay.
- Claiming that the bike or its display is connected when iOS only accepted a Wi-Fi configuration.

## Constraints and calls

- Use SwiftUI, AVFoundation, NetworkExtension, and Security already provided by iOS; keep iOS 16.0 and Swift 5; add no third-party packages.
- Ask for camera access only after the rider taps Scan.
- Require a rider action to save and join a scanned network. iOS presents its own Wi-Fi approval prompt.
- Save a persistent Wi-Fi configuration so it remains available after the app backgrounds; offer removal from the Bike tab. The rider can also manage the network in iOS Settings.
- Do not log or write the QR payload or password to the bike metadata file.

## Approaches considered

1. **Native QR scanner + hotspot configuration (selected):** fits the existing SwiftUI iOS app, keeps credentials local, and uses Apple's supported accessory Wi-Fi flow.
2. **Port Android's QR/networking implementation:** the Android camera and Wi-Fi APIs do not map to iOS and would add unnecessary code.
3. **Manual network setup only:** avoids a scanner but does not satisfy the agreed QR-first flow for the Zontes target.

## Interaction

Bike tab → Scan QR → review the detected name and SSID → Save & Join → approve the iOS Wi-Fi prompt. Unsupported P2P or phone-hotspot QR codes show a clear message. Saved bikes can be joined again or removed. A successful configuration request is described as such; it is not described as a confirmed bike connection.

## Remaining work

Test with real Zontes 125X/125V dashboards and an iPhone. This slice does not establish whether CarPlay or another iOS projection path can use the connection.
