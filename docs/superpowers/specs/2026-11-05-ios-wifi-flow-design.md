# RideScreen iOS Wi-Fi pairing flow

## Intent

Make pairing a bike Wi-Fi access point understandable and usable with either a signed Hotspot Configuration entitlement or a free Apple ID that must join Wi-Fi manually. The rider should not mistake an accepted configuration request for a confirmed bike connection.

## Approaches

- Automatic join only: retain `NEHotspotConfigurationManager`; it cannot serve free Apple ID installs that lack the entitlement.
- Manual join only: works around the entitlement limit but discards automatic joining for properly signed installs.
- Automatic join with a clear manual fallback (selected): keep the supported iOS API, explain code 8 without blaming the QR, and guide the rider through Settings using the saved SSID/password.

## Design

- Keep QR scanning and local bike storage as-is.
- Keep automatic join for signed builds that carry Hotspot Configuration.
- When automatic join fails, present the manual instructions immediately: show the SSID, let the rider copy the password, and give the Settings > Wi-Fi steps. Keep the same flow available from the saved-bike card before attempting an automatic join.
- After the rider returns, let them explicitly confirm they joined manually. Label that state as rider-confirmed and unverified; do not infer the SSID or claim the dash service is connected.
- Preserve the current successful-apply message: iOS accepting the request is not proof the bike display link works.
- Keep removal limited to RideScreen-managed Wi-Fi configuration; do not remove a network the rider added in Settings.

## Constraints and non-goals

- This change covers QR/AP Wi-Fi setup and the free-account manual fallback. It does not implement Wi-Fi Direct, Carbit/EasyConn communication, video projection, or CarPlay navigation behavior.
- The MOTO-HUB iOS release repository publishes binaries and documents its manual Wi-Fi path, but not its iOS source. Implement this flow from platform APIs and the repository's existing code; do not copy its binary or claim a direct source port.
- The current CarPlay diagnostic remains a separate local receiver probe and must not be presented as a bike Wi-Fi verification.
- Keep credentials in the existing Keychain path; never include the password in diagnostics.
- Build and real-device validation require Codemagic/Xcode and an iPhone; the current host is Windows.

## Open implementation detail

Use the existing Bike screen and SwiftUI alert/sheet patterns. Do not add a dependency or a new pairing subsystem.
