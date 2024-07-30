//
//  NavigationManager.swift
//  Joyride
//
//  Created by Maximillian Ludwick on 7/22/24.
//

import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit
import MapboxMaps
import UIKit

enum NavigationError: Error {
    case userLocationNotAvailable
    case invalidDestination
    case routeCalculationFailed
    case presentationFailed
}

@MainActor
class NavigationManager {
    static let mapboxNavigationProvider = MapboxNavigationProvider(coreConfig: .init())
    static var mapboxNavigation: MapboxNavigation {
        return mapboxNavigationProvider.mapboxNavigation
    }
    
    static func startNavigation(to coordinate: CLLocationCoordinate2D, name: String, mapView: MapView?, styleURI: String, navigationStateManager: NavigationStateManager) async throws {
        print("DEBUG: NavigationManager.startNavigation called with destination: \(name) at \(coordinate)")

        let userLocation = try await getUserLocation(mapView: mapView)
        print("DEBUG: User location found: \(userLocation)")

        let origin = Waypoint(coordinate: userLocation)
        let destination = Waypoint(coordinate: coordinate, name: name)

        let options = NavigationRouteOptions(waypoints: [origin, destination])

        do {
            let request = mapboxNavigation.routingProvider().calculateRoutes(options: options)
            let result = await request.result

            switch result {
            case .success(let navigationRoutes):
                let navigationOptions = NavigationOptions(
                    mapboxNavigation: mapboxNavigation,
                    voiceController: mapboxNavigationProvider.routeVoiceController,
                    eventsManager: mapboxNavigationProvider.eventsManager()
                )

                let navigationViewController = NavigationViewController(
                    navigationRoutes: navigationRoutes,
                    navigationOptions: navigationOptions
                )
                navigationViewController.modalPresentationStyle = .fullScreen

                // Set the delegate
                navigationViewController.delegate = NavigationViewControllerDelegateImpl(navigationStateManager: navigationStateManager)

                // Set the initial camera position to the user's location
                navigationViewController.navigationMapView?.mapView.camera.ease(
                    to: CameraOptions(center: userLocation, zoom: 15),
                    duration: 0
                )

                if let styleURI = StyleURI(rawValue: styleURI) {
                    await navigationViewController.navigationMapView?.mapView.mapboxMap.loadStyle(styleURI)
                }

                navigationViewController.view.backgroundColor = .dynamicNavigationBackground

                var compassOptions: CompassViewOptions? = navigationViewController.navigationMapView?.mapView.ornaments.options.compass
                compassOptions?.position = .topRight

                var logoOptions: LogoViewOptions? = navigationViewController.navigationMapView?.mapView.ornaments.options.logo
                logoOptions?.position = .bottomLeft

                navigationViewController.navigationMapView?.mapView.ornaments.options.compass = compassOptions ?? CompassViewOptions()
                navigationViewController.navigationMapView?.mapView.ornaments.options.logo = logoOptions ?? LogoViewOptions()

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    await MainActor.run {
                        rootViewController.present(navigationViewController, animated: true)
                        navigationStateManager.isNavigating = true
                    }
                    print("DEBUG: Navigation view controller presented successfully")
                } else {
                    throw NavigationError.presentationFailed
                }

            case .failure(let error):
                print("Error calculating route: \(error.localizedDescription)")
                throw NavigationError.routeCalculationFailed
            }
        } catch {
            print("DEBUG: Navigation failed to start: \(error.localizedDescription)")
            throw error
        }
    }

    static func getUserLocation(mapView: MapView?) async throws -> CLLocationCoordinate2D {
        for _ in 0..<10 { // Try up to 10 times
            if let userLocation = mapView?.location.latestLocation?.coordinate,
               CLLocationCoordinate2DIsValid(userLocation) {
                return userLocation
            }
            try await Task.sleep(nanoseconds: 100_000_000) // Wait 0.2 seconds before trying again
        }
        throw NavigationError.userLocationNotAvailable
    }
}

class NavigationViewControllerDelegateImpl: NSObject, NavigationViewControllerDelegate {
    let navigationStateManager: NavigationStateManager
    
    init(navigationStateManager: NavigationStateManager) {
        self.navigationStateManager = navigationStateManager
    }
    
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        navigationStateManager.isNavigating = false
    }
}
