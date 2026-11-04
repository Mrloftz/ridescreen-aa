// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct TripDetailView: View {
    let ride: Ride

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var routePoints: [TrackPoint] {
        ride.points.filter {
            $0.latitude.isFinite && (-90...90).contains($0.latitude)
                && $0.longitude.isFinite && (-180...180).contains($0.longitude)
        }
    }
    private var averageSpeedKmh: Double {
        guard ride.movingTime > 0 else { return 0 }
        return max(0, ride.distanceMeters / ride.movingTime * 3.6)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if routePoints.count >= 2 {
                    TripRouteMap(points: routePoints, maximumSpeed: ride.maxSpeedMetersPerSecond)
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.quaternary, lineWidth: 1)
                        }

                    HStack(spacing: 14) {
                        Label("Slower", systemImage: "circle.fill")
                            .foregroundStyle(Color.blue)
                        Label("Faster", systemImage: "circle.fill")
                            .foregroundStyle(Color.red)
                        Spacer()
                        Text("by speed")
                            .foregroundStyle(RideScreenTheme.secondary)
                    }
                    .font(.caption)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundStyle(RideScreenTheme.secondary)
                        Text("Route unavailable")
                            .font(.headline)
                        Text("This ride does not have enough valid GPS points to draw a route.")
                            .font(.subheadline)
                            .foregroundStyle(RideScreenTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 210)
                    .padding()
                    .rideCard(padding: 20, radius: 20)
                }

                Text("\(ride.startedAt.formatted(date: .complete, time: .shortened)) – \(ride.endedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(RideScreenTheme.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    RideMetricCard(
                        title: "Distance",
                        value: (ride.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1))),
                        unit: "km"
                    )
                    RideMetricCard(title: "Moving time", value: durationText(ride.movingTime), unit: nil)
                    RideMetricCard(
                        title: "Average speed",
                        value: averageSpeedKmh.formatted(.number.precision(.fractionLength(1))),
                        unit: "km/h"
                    )
                    RideMetricCard(
                        title: "Maximum speed",
                        value: (ride.maxSpeedMetersPerSecond * 3.6).formatted(.number.precision(.fractionLength(0))),
                        unit: "km/h"
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Ride details")
        .navigationBarTitleDisplayMode(.inline)
        .background(RideScreenTheme.background.ignoresSafeArea())
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

private struct TripRouteMap: UIViewRepresentable {
    let points: [TrackPoint]
    let maximumSpeed: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.overrideUserInterfaceStyle = .dark
        context.coordinator.render(points: points, maximumSpeed: maximumSpeed, on: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.render(points: points, maximumSpeed: maximumSpeed, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var didRender = false
        private var colors: [ObjectIdentifier: UIColor] = [:]

        func render(points: [TrackPoint], maximumSpeed: Double, on map: MKMapView) {
            guard !didRender, points.count >= 2 else { return }
            didRender = true
            let coordinates = points.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }

            var runs: [(coordinates: [CLLocationCoordinate2D], bucket: Int)] = []
            var run = [coordinates[0]]
            var bucket = speedBucket(points[0].speedMetersPerSecond, maximumSpeed: maximumSpeed)
            for index in 1..<points.count {
                let nextBucket = speedBucket(points[index].speedMetersPerSecond, maximumSpeed: maximumSpeed)
                if nextBucket != bucket {
                    run.append(coordinates[index])
                    if run.count >= 2 { runs.append((run, bucket)) }
                    run = [coordinates[index]]
                    bucket = nextBucket
                } else {
                    run.append(coordinates[index])
                }
            }
            if run.count >= 2 { runs.append((run, bucket)) }

            let overlays = runs.map { run in
                let polyline = MKPolyline(coordinates: run.coordinates, count: run.coordinates.count)
                colors[ObjectIdentifier(polyline)] = Self.speedColor(run.bucket)
                return polyline
            }
            map.addOverlays(overlays, level: .aboveLabels)

            let start = MKPointAnnotation()
            start.coordinate = coordinates[0]
            start.title = "Start"
            let end = MKPointAnnotation()
            end.coordinate = coordinates[coordinates.count - 1]
            end.title = "End"
            map.addAnnotations([start, end])

            let route = MKPolyline(coordinates: coordinates, count: coordinates.count)
            let bounds = route.boundingMapRect
            let width = max(bounds.size.width, 1_200)
            let height = max(bounds.size.height, 1_200)
            let paddingX = max(width * 0.15, 900)
            let paddingY = max(height * 0.15, 900)
            let visibleRect = MKMapRect(
                x: bounds.midX - width / 2 - paddingX,
                y: bounds.midY - height / 2 - paddingY,
                width: width + 2 * paddingX,
                height: height + 2 * paddingY
            )
            map.setVisibleMapRect(
                visibleRect,
                edgePadding: UIEdgeInsets(top: 30, left: 24, bottom: 30, right: 24),
                animated: false
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = colors[ObjectIdentifier(polyline)] ?? .systemBlue
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let identifier = "trip-endpoint"
            let marker = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            marker.annotation = annotation
            marker.canShowCallout = true
            marker.markerTintColor = (annotation.title ?? "") == "Start" ? .systemGreen : .systemRed
            return marker
        }

        private func speedBucket(_ speed: Double, maximumSpeed: Double) -> Int {
            let top = max(maximumSpeed.isFinite ? maximumSpeed : 0, 1)
            let value = speed.isFinite ? max(speed, 0) : 0
            return Int((min(value / top, 1) * 9).rounded(.down))
        }

        private static func speedColor(_ bucket: Int) -> UIColor {
            let fraction = CGFloat(bucket) / 9
            return UIColor(hue: 0.62 * (1 - fraction), saturation: 0.9, brightness: 0.92, alpha: 1)
        }
    }
}
