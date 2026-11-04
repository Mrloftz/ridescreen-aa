# iOS Trip Capture Design

**Status:** Initial implementation slice, started at the user's direction to begin iOS development.

## Intent

Build the native iPhone counterpart to RideScreen AA. The agreed product scope is feature parity with Android, local iPhone data for the first release, QR plus Wi-Fi access-point bike pairing for Zontes 125X/125V, country selection for fuel prices, user-confirmed SMS after a crash alert, and a later Apple Watch app. CarPlay will be evaluated after the iPhone app is clearer.

This first vertical slice makes ride logging usable on iPhone: start and stop a GPS ride, see live metrics, save it locally, and browse saved rides. It is a foundation for the complete app, not a feature-complete release.

## Goals

- Add a native iOS app target under `ios/`, using SwiftUI and Core Location.
- Record GPS points, live speed, distance, moving time, and maximum speed.
- Filter poor and implausible fixes using the thresholds already used by Android.
- Save meaningful rides and a recovery checkpoint on the device; show saved rides newest first.
- Continue an explicitly started recording in the background with the system's location indicator.

## Non-goals for this slice

- Bike QR/Wi-Fi connection, automatic ride start, Android data import, cloud sync, or remote sharing.
- Route maps, colored tracks, ride naming, video, heat maps, maintenance, fuel prices, crash detection, SMS, CarPlay, and watchOS.
- Any location upload or account requirement.

## Constraints and implementation calls

- Use a standalone SwiftUI app in `ios/RideScreen/`; do not introduce Kotlin Multiplatform or third-party dependencies.
- Set the deployment target to iOS 16.0 and use Swift language mode 5 for broad device coverage.
- Use `CLLocationManager`. Ask for When In Use authorization only when the rider starts a ride. If iOS grants reduced accuracy, request temporary full accuracy with a ride-specific usage string; if the rider declines, explain how to enable Precise Location in Settings. Set `allowsBackgroundLocationUpdates` while recording and include `UIBackgroundModes` with `location`; iOS shows its location indicator while the app records in the background. Apple documents this behavior in [Core Location background updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates), [When In Use authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services), and [temporary full accuracy](https://developer.apple.com/documentation/corelocation/cllocationmanager/requesttemporaryfullaccuracyauthorization%28withpurposekey%3A%29).
- Persist Codable ride data atomically as JSON under Application Support. Checkpoint an active ride about every 30 seconds and recover a meaningful checkpoint as a finished ride on next launch. A write failure preserves the last valid archive and exposes a retry action for an unsaved ride.
- Port Android's core trip thresholds: 35 m maximum reported accuracy, 75 m/s maximum plausible jump speed, 0.8 m/s movement threshold, 300 m and 30 seconds minimum to save, a 10 minute moving-gap bridge, 3 minute idle split, and 30 second checkpoint interval.
- Reject fixes older than the current ride start or at/before the last accepted point. When Core Location has no speed reading, estimate movement only after net displacement exceeds 1.5 times the combined reported horizontal accuracy; sub-threshold GPS jitter must not add distance or moving time.
- The app bundle identifier will be `dev.zanderp.opencfmoto.ios` unless signing setup requires the owner to choose a team-specific identifier.
- The current development host has no Xcode or Swift compiler. The source can be prepared here, but building and device validation require macOS with Xcode.

## Approaches considered

1. **Native SwiftUI app (selected implementation call):** Core Location and iOS local storage fit ride recording and the agreed platform-specific integrations. This keeps the Android code intact and avoids a new cross-platform layer.
2. **Kotlin Multiplatform:** could share domain logic, but the existing app is Android-only and its recorder is coupled to Android APIs; introducing shared infrastructure would slow the first iPhone slice.
3. **Web wrapper:** would reduce initial UI code but gives a poorer fit for background GPS, sensors, local files, and later iOS integrations.

## Interaction

- The Ride tab shows current speed, distance, moving time, location permission status, and a Start/Stop control.
- Permission is requested only after Start. If permission is denied, the app explains that location access must be enabled in iOS Settings.
- The Trips tab lists locally saved rides with date, distance, moving time, and maximum speed.
- A ride shorter than the Android save thresholds is discarded when stopped.

## Remaining product work

This slice does not decide the final dashboard, map experience, QR protocol details, fuel-price providers, crash sensor tuning, country coverage, or CarPlay category. Those remain separate design and implementation slices before a feature-complete release.
