# RideScreen for iOS

The iOS app is a native SwiftUI application. Build and run it on macOS with Xcode by opening `RideScreen.xcodeproj` and selecting the RideScreen scheme.

The Bike tab can scan Carbit / EasyConnect pairing QR codes that provide a Wi-Fi access point, save a bike locally, and ask iOS to join the network. Camera access is requested only when scanning. Bike names and SSIDs are stored in Application Support; Wi-Fi passwords are stored in Keychain. iOS presents its own approval prompt and remembers the configured network until it is removed from the Bike tab or iOS Settings. This slice does not connect to the bike display service or provide projection. Wi-Fi Direct and phone-hotspot QR flows are not supported yet.

Tap a saved ride in Trips to open its route map and distance, moving time, average speed, and maximum speed. The route is drawn from the saved GPS points and colored by speed. MapKit supplies the basemap; the saved route remains on the device, but map tiles may require an internet connection.

The current development host is Windows and does not include Xcode or Swift, so it cannot build or run this target. Device testing is required for GPS accuracy, background recording, camera permission behavior, Hotspot Configuration signing, and QR / Wi-Fi behavior with Zontes 125X and 125V dashboards.
