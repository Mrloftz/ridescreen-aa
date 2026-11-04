# iOS Trip Details Implementation Plan

> **For agentic workers:** Implement inline in the existing `feat/ios-foundation` worktree.

**Goal:** Open each saved ride to a MapKit route view and ride statistics.

**Architecture:** Use a `UIViewRepresentable` around `MKMapView` to render grouped speed-colored `MKPolyline` overlays and endpoint annotations. Add a SwiftUI detail screen using the existing `Ride` model and link each Trips row to it.

**Tech Stack:** Swift 5, SwiftUI, MapKit; iOS 16.0.

**Spec:** `docs/superpowers/specs/2026-11-04-ios-trip-details-design.md`

## Global Constraints

- iOS 16.0 minimum and Swift language mode 5.
- No third-party dependencies or API keys.
- Render existing local points without requesting location permission.
- Do not promise offline basemap tiles.
- Keep map overlays proportional to speed runs, not raw sample count.

## Files

- Create `ios/RideScreen/TripDetailView.swift` for the ride summary and `MKMapView` wrapper.
- Modify `ios/RideScreen/ContentView.swift` so a trip row opens its detail screen.
- Modify `ios/RideScreen.xcodeproj/project.pbxproj` to include the new source.
- Update `ios/README.md` with map data and network behavior.

## Review Focus

- Empty and one-point routes show stats with a clear unavailable-map message.
- Invalid coordinates are skipped instead of crashing MapKit.
- Repeated or stationary coordinates still produce a sane map region.
- High sample counts are grouped into speed buckets rather than creating one overlay per point.
- Missing or zero moving time never causes a division-by-zero average speed.

### Task 1: Add trip detail map and summary

- [x] Create the MapKit wrapper, speed runs, endpoint markers, and route framing.
- [x] Add date, distance, moving time, average speed, and maximum speed to the detail screen.

### Task 2: Wire Trips navigation and document

- [x] Link each saved ride row to its detail screen and add the source to the Xcode project.
- [x] Document the MapKit basemap/network limitation and inspect the final integration.
- [x] Do not add or run tests or builds in this Windows environment; Xcode and Swift are unavailable.
