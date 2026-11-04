# iOS Wi-Fi and CarPlay Diagnostics Follow-up

**Status:** Proceeding under the user's existing request to continue iOS development and test on the Zontes 368E.

## Intent

Make bike Wi-Fi setup usable when the unsigned IPA cannot apply a network profile, and make the
CarPlay diagnostic describe what it actually checks.

## Evidence and constraints

- RideScreen uses `NEHotspotConfigurationManager.apply` and currently hides most iOS error codes.
- The `ios-unsigned` IPA is re-signed by the sideloading tool. The resulting signature may not carry
  the Hotspot Configuration entitlement from the source entitlements file.
- The supplied MOTO-HUB screen copies the bike password and guides the rider to join in iOS Wi-Fi
  settings.
- RideScreen's probe requests `127.0.0.1:8969/stream`. The iCarCast user guide describes `This iPhone`
  as running CarPlay on the same phone and does not document the probe's hard-coded local URL.

## Approaches

1. Require a signed provisioning profile with Hotspot Configuration. This can preserve automatic
   Wi-Fi setup but depends on Apple signing configuration and does not help the current unsigned IPA.
2. Use manual Wi-Fi setup only. This matches MOTO-HUB and works without the app entitlement, but
   adds a Settings step even when automatic setup is available.
3. Keep the automatic attempt, expose its error code, and show a manual copy-password fallback;
   label the hard-coded local URL check as experimental and avoid claiming it detects iCarCast itself.

The current development request authorizes approach 3. It preserves the existing automatic path and
gives the rider the documented manual path when the sideloaded build cannot configure Wi-Fi.

## Scope

- Add manual Wi-Fi instructions and a copy-password action after a connection attempt, including
  from the saved-bike screen.
- Include the iOS error domain and code in failed automatic setup results.
- Add Wi-Fi setup outcomes to the shareable diagnostic report without including the SSID or password.
- Clarify in the diagnostic UI and exported log that the probe only checks RideScreen's local test
  URL; it does not verify iCarCast state or stream video to the bike.
- Do not add a native CarPlay scene or claim dashboard projection in this follow-up.
