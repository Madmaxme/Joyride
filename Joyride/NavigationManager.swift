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
    
    static func startNavigation(to coordinate: CLLocationCoordinate2D, name: String, mapView: MapView?, styleURI: String) async throws {
        print("DEBUG: NavigationManager.startNavigation called with destination: \(name) at \(coordinate)")
        
        guard CLLocationCoordinate2DIsValid(coordinate) && coordinate.latitude != 0 && coordinate.longitude != 0 else {
            print("DEBUG: Invalid destination coordinates")
            throw NavigationError.invalidDestination
        }
        
        guard let userLocation = mapView?.location.latestLocation?.coordinate else {
            print("DEBUG: User location not available")
            throw NavigationError.userLocationNotAvailable
        }
        
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
                
                if let styleURI = StyleURI(rawValue: styleURI) {
                    navigationViewController.navigationMapView?.mapView.mapboxMap.loadStyle(styleURI)
                }
                
                navigationViewController.view.backgroundColor = .dynamicNavigationBackground
                
                var compassOptions = navigationViewController.navigationMapView?.mapView.ornaments.options.compass
                compassOptions?.position = .topRight
                
                var logoOptions = navigationViewController.navigationMapView?.mapView.ornaments.options.logo
                logoOptions?.position = .bottomLeft
                
                navigationViewController.navigationMapView?.mapView.ornaments.options.compass = compassOptions ?? CompassViewOptions()
                navigationViewController.navigationMapView?.mapView.ornaments.options.logo = logoOptions ?? LogoViewOptions()
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    await MainActor.run {
                        rootViewController.present(navigationViewController, animated: true)
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
}
