// SPDX-License-Identifier: AGPL-3.0-or-later
import CarPlay
import MapKit
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var mapViewController: CarPlayMapViewController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        let mapViewController = CarPlayMapViewController()
        self.mapViewController = mapViewController
        window.rootViewController = mapViewController

        let mapTemplate = CPMapTemplate()
        let recenterButton = CPMapButton { [weak mapViewController] _ in
            mapViewController?.recenterOnRider()
        }
        recenterButton.image = UIImage(systemName: "location.fill")
        mapTemplate.mapButtons = [recenterButton]

        interfaceController.setRootTemplate(mapTemplate, animated: true)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        mapViewController = nil
    }
}

@MainActor
private final class CarPlayMapViewController: UIViewController {
    private let mapView = MKMapView(frame: .zero)

    override func loadView() {
        view = mapView
        mapView.mapType = .standard
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.pointOfInterestFilter = .excludingAll
    }

    func recenterOnRider() {
        if let location = mapView.userLocation.location {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1_500,
                    longitudinalMeters: 1_500
                ),
                animated: true
            )
        } else {
            mapView.userTrackingMode = .follow
        }
    }
}
