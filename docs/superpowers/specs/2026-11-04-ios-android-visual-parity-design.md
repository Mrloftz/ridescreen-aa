# iOS Android Visual Parity Design

**Status:** Approved by the user's direct request to start making the iOS app look like Android.

## Intent

Bring the current RideScreen iOS screens into the same visual identity as the Android app while the
user tests Wi-Fi and iCarCast on the existing build. The iOS app should feel like the same product,
not a default SwiftUI sample.

## Scope

- Apply the Android matte-green palette, Archivo Black display values, outlined dark cards, gold accent, and
  confident primary buttons to the existing Ride, Trips, Garage, bike-review, and Project CarPlay
  screens.
- Keep the existing SwiftUI navigation, camera QR scanner, iOS Wi-Fi approval, and share sheet.
- Keep user-facing copy and current feature behavior unless needed to make the flow clearer.
- Limit this pass to visual parity for existing iOS features. It does not port all Android-only
  features or implement dashboard video projection.

## Android reference values

- Background `#1A231D`; surface `#243028`; raised surface `#2D3B31`; outline `#3D4F42`.
- Primary text `#F1F4EC`; secondary text `#AEBAAA`.
- Gold accent `#D1A955`; dark gold `#A9873E`; status green `#5BD47A`; busy amber `#E9C46A`;
  error red `#FF6B5E`.
- Archivo Black for display values; system text for body and labels. The available Android regular,
  medium, semibold, and extrabold font files share the same PostScript name, so they are not bundled
  as separate iOS fonts.
- Cards use 18-22 point corners and thin outlines; primary actions use a tall rounded shape.

## Approach

Add one small SwiftUI theme and reuse it across current screens. Preserve native iOS interactions and
system permission prompts. A full port of Android screens and feature workflows is outside this
visual pass because many Android features have no corresponding iOS implementation yet.

## Acceptance

- iOS's current tabs and tested bike/projection flows use the Android palette, cards, and display
  typography rather than system grouped-list colors.
- QR, bike data, Wi-Fi actions, diagnostics, and navigation retain their current behavior.
- Xcode project bundles the verified Archivo Black display font and exposes its PostScript name to
  SwiftUI.
