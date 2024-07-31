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
import Combine

enum NavigationError: Error {
    case userLocationNotAvailable
    case invalidDestination
    case routeCalculationFailed
    case presentationFailed
    case mapViewNotInitialized
}

@MainActor
class NavigationManager {
    static let mapboxNavigationProvider = MapboxNavigationProvider(coreConfig: .init())
    static var mapboxNavigation: MapboxNavigation {
        return mapboxNavigationProvider.mapboxNavigation
    }
    
    static func startNavigation(to coordinate: CLLocationCoordinate2D, name: String, mapView: MapView?, styleURI: String, navigationStateManager: NavigationStateManager) async throws {
        print("DEBUG: NavigationManager.startNavigation called with destination: \(name) at \(coordinate)")
        
        guard let mapView = mapView, mapView.frame.size != .zero else {
            print("DEBUG: MapView is not properly initialized")
            throw NavigationError.mapViewNotInitialized
        }
        
        // Set the flag to prevent automatic camera updates
        if let gestureManagerDelegate = mapView.gestures.delegate {
            if let mapManager = gestureManagerDelegate as? MapManager {
                mapManager.isNavigationStarting = true
            } else {
                print("DEBUG: GestureManager delegate is not of type MapManager")
            }
        } else {
            print("DEBUG: GestureManager delegate is nil")
        }

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
                print("DEBUG: Route calculation successful")
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

                // Set initial camera state
                let initialCameraOptions = CameraOptions(center: userLocation, zoom: 15, bearing: 0, pitch: 0)
                navigationViewController.navigationMapView?.mapView.camera.ease(
                    to: initialCameraOptions,
                    duration: 0,
                    completion: nil
                )
                
                // Reset the flag after navigation has started
                if let gestureManagerDelegate = mapView.gestures.delegate {
                    if let mapManager = gestureManagerDelegate as? MapManager {
                        mapManager.isNavigationStarting = false
                    } else {
                        print("DEBUG: GestureManager delegate is not of type MapManager")
                    }
                } else {
                    print("DEBUG: GestureManager delegate is nil")
                }

                // Set the delegate
                navigationViewController.delegate = NavigationViewControllerDelegateImpl(navigationStateManager: navigationStateManager)

                // Configure the navigation view controller
                configureNavigationViewController(navigationViewController, userLocation: userLocation, routes: navigationRoutes, styleURI: styleURI)

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    await MainActor.run {
                        rootViewController.present(navigationViewController, animated: false) {
                            navigationStateManager.isNavigating = true
                            print("DEBUG: Navigation view controller presented")
                        }
                    }
                    print("DEBUG: Navigation view controller presentation scheduled")
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

    private static func configureNavigationViewController(_ navigationViewController: NavigationViewController, userLocation: CLLocationCoordinate2D, routes: NavigationRoutes, styleURI: String) {
        print("DEBUG: Configuring NavigationViewController")
        
        guard let navigationMapView = navigationViewController.navigationMapView else {
            print("DEBUG: NavigationMapView is nil")
            return
        }
        
        // Set initial camera to user location with a zoom level that makes sense for navigation
        let initialCameraOptions = CameraOptions(center: userLocation, zoom: 15, bearing: 0, pitch: 0)
        navigationMapView.mapView.camera.ease(to: initialCameraOptions, duration: 0)
        
        // Update viewport padding
        navigationMapView.viewportPadding = UIEdgeInsets(top: 20, left: 20, bottom: 40, right: 20)
        
        // Configure the NavigationCamera
        navigationMapView.navigationCamera.viewportPadding = navigationMapView.viewportPadding
        
        
        
        // Load style and set initial camera position
        if let styleURI = StyleURI(rawValue: styleURI) {
            navigationMapView.mapView.mapboxMap.loadStyleURI(styleURI) { [weak navigationMapView] error in
                if let error = error {
                    print("DEBUG: Failed to load map style: \(error.localizedDescription)")
                } else {
                    print("DEBUG: Map style loaded successfully")
                    
                    // Set the camera position immediately after style load
                    navigationMapView?.mapView.camera.ease(to: initialCameraOptions, duration: 0)
                    
                    // Showcase the route without animation
                    navigationMapView?.showcase(
                        routes,
                        routesPresentationStyle: .all(),
                        animated: false,
                        duration: 0
                    )
                    
                    // Force the camera to update to following state
                    navigationMapView?.update(navigationCameraState: .following)
                }
            }
        }

        navigationViewController.view.backgroundColor = .white

        // Configure other settings
        navigationMapView.showsAlternatives = true
        navigationMapView.routeLineTracksTraversal = true
        navigationMapView.showsRestrictedAreasOnRoute = true
        
        print("DEBUG: Initial camera state: \(navigationMapView.mapView.mapboxMap.cameraState)")
    }
    
    private static func ensureCameraIsOnUserLocation(_ navigationViewController: NavigationViewController, userLocation: CLLocationCoordinate2D) {
        guard let navigationMapView = navigationViewController.navigationMapView else {
            print("DEBUG: NavigationMapView is nil when trying to ensure camera is on user location")
            return
        }
        
        let currentCenter = navigationMapView.mapView.mapboxMap.cameraState.center
        let distance = userLocation.distance(to: currentCenter)
        
        if distance > 1000 { // If the camera is more than 1km away from the user location
            print("DEBUG: Camera is far from user location. Adjusting...")
            let cameraOptions = CameraOptions(center: userLocation, zoom: 15)
            navigationMapView.mapView.camera.ease(to: cameraOptions, duration: 1.0)
        } else {
            print("DEBUG: Camera is already close to user location")
        }
    }

    static func getUserLocation(mapView: MapView?) async throws -> CLLocationCoordinate2D {
        for attempt in 1...20 {
            if let userLocation = mapView?.location.latestLocation?.coordinate,
               CLLocationCoordinate2DIsValid(userLocation) {
                print("DEBUG: User location found on attempt \(attempt): \(userLocation)")
                return userLocation
            }
            print("DEBUG: Attempt \(attempt) to get user location failed")
            try await Task.sleep(nanoseconds: 100_000_000) // Wait 0.1 seconds before trying again
        }
        print("DEBUG: Failed to get user location after 20 attempts")
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
        print("DEBUG: NavigationViewController dismissed, canceled: \(canceled)")
    }
    
    func navigationViewController(_ navigationViewController: NavigationViewController, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
        print("DEBUG: Navigation progress updated - step: \(progress.currentLegProgress.stepIndex)/\(progress.currentLeg.steps.count), distance remaining: \(progress.distanceRemaining)")
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let thisLocation = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let otherLocation = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return thisLocation.distance(from: otherLocation)
    }
}
