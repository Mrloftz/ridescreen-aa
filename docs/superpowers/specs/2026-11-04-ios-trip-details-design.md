# iOS Trip Details Design

**Status:** Next iOS slice, continuing the user's feature-parity direction.

## Intent

Let riders open a saved ride from Trips, see its route on a map, and review the main ride statistics.

## Goals

- Make each saved ride open a detail screen.
- Draw the locally recorded GPS route, colored blue for slower points and red for faster points, with Start and End markers.
- Fit the route in the map when the detail screen opens.
- Show date, distance, moving time, average speed, and maximum speed.

## Non-goals

- All-rides maps, heat maps, route comparison, trip names, GPX export/sharing, trip video, CarPlay, and Android data import.
- Downloading or caching offline maps as part of this slice.

## Constraints and calls

- Use MapKit's `MKMapView`, `MKPolyline`, and `MKPolylineRenderer`, wrapped for SwiftUI. `MKMapView` supports overlays and a fit-to-visible-rect operation on the existing iOS 16 target.
- Keep route points on device and draw from the saved `Ride.points`; request no location permission to view an existing trip.
- Use MapKit's native basemap, with no external SDK or API key. The route overlay remains available from saved coordinates, while map tiles may need network access.
- Group neighboring points into speed buckets so rendering uses a small number of overlays instead of one overlay per GPS sample.

## Approaches considered

1. **MapKit native map view (selected):** built into iOS and supports the existing iOS 16 deployment target, speed-colored polyline overlays, and endpoint annotations without an added SDK.
2. **SwiftUI `Map` only:** less wrapper code, but per-run custom overlay rendering is a worse fit for speed-colored routes on the iOS 16 minimum.
3. **External map SDK:** adds a dependency and usually a provider key or account for a screen that the system framework can already provide.

## Interaction

Trips → tap ride → route map and summary. The route is framed on open; the rider can pan and zoom. If the saved ride has fewer than two usable points, show a route-unavailable message and retain the ride statistics.

## Remaining work

Match the full Android map screen later, including all-rides/heat-map views, trip comparison, GPX sharing, and video actions. Validate map rendering on an iPhone with real saved GPS tracks.
