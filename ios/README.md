# RideScreen for iOS

The iOS app is a native SwiftUI application. Build and run it on macOS with Xcode by opening `RideScreen.xcodeproj` and selecting the RideScreen scheme.

The Bike tab can scan Carbit / EasyConnect pairing QR codes that provide a Wi-Fi access point, save a bike locally, and ask iOS to join the network. Camera access is requested only when scanning. Bike names and SSIDs are stored in Application Support; Wi-Fi passwords are stored in Keychain. iOS presents its own approval prompt and remembers the configured network until it is removed from the Bike tab or iOS Settings. Wi-Fi Direct and phone-hotspot QR flows are not supported yet.

## CarPlay receiver checkpoint

**Project CarPlay** on a saved bike checks the separate iCarCast app at the fixed loopback endpoint `127.0.0.1:8969`. It records only bounded stream metadata (status, content type, byte count, framing, and H.264 NAL types), never sampled video or Wi-Fi credentials. This checkpoint does not yet send video to the dashboard and RideScreen does not declare a CarPlay scene or entitlement.

On the test iPhone:

1. Install and configure iCarCast, join the Zontes Wi-Fi, then start **This iPhone** in iCarCast.
2. Return to RideScreen, open the saved Zontes 368E, tap **Project CarPlay**, then **Probe iCarCast**.
3. Tap **Share diagnostic** and send the exported text report after either success or failure.

## Codemagic IPA builds

Import this repository into Codemagic and select `codemagic.yaml`. Run `ios-unsigned` first. Its artifacts include `RideScreen-unsigned.ipa` and the Xcode logs. Install the IPA by importing it into AltStore Classic, SideStore, or Sideloadly; those tools re-sign the unsigned app with your Apple ID. A free Apple ID normally requires refreshing the sideloaded app every seven days.

Re-signing can remove capabilities that are not present in the replacement profile. If **Join Wi-Fi** cannot configure the bike network, join the Zontes Wi-Fi manually in iOS Settings and return to RideScreen. The receiver probe itself does not depend on programmatic Wi-Fi joining.

The opt-in `ios-signed` workflow requires a matching development certificate and provisioning profile for `dev.zanderp.opencfmoto.ios` uploaded or fetched in Codemagic. No signing certificate, profile, private key, or App Store Connect secret belongs in this repository. A profile must explicitly allow any required capabilities, including Hotspot Configuration.

Tap a saved ride in Trips to open its route map and distance, moving time, average speed, and maximum speed. The route is drawn from the saved GPS points and colored by speed. MapKit supplies the basemap; the saved route remains on the device, but map tiles may require an internet connection.

The current development host is Windows and cannot run Xcode. Foundation-only Swift harnesses can run in the Swift Docker image, while Codemagic performs the authoritative Xcode build. Device testing is required for the iCarCast receiver endpoint, GPS accuracy, background recording, camera permission behavior, Hotspot Configuration signing, and QR / Wi-Fi behavior with the Zontes dashboard.
