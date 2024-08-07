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
import MapKit

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
            print("DEBUG: MapView is not properly initialized. Frame: \(mapView?.frame ?? .zero)")
            throw NavigationError.mapViewNotInitialized
        }
        
        print("DEBUG: MapView frame: \(mapView.frame)")
        print("DEBUG: MapView bounds: \(mapView.bounds)")
        
        if let gestureManagerDelegate = mapView.gestures.delegate as? MapManager {
            gestureManagerDelegate.isNavigationStarting = true
            print("DEBUG: Set isNavigationStarting to true")
        }
        
        let userLocation = try await getUserLocation(mapView: mapView)
        print("DEBUG: User location found: \(userLocation)")
        
        let origin = Waypoint(coordinate: userLocation)
        let destination = Waypoint(coordinate: coordinate, name: name)
        
        // Create multiple route options with different settings
        let routeOptions = [
            createRouteOptions(origin: origin, destination: destination, profile: .automobile),
            createRouteOptions(origin: origin, destination: destination, profile: .automobileAvoidingTraffic)
        ]
        
        var allRoutes: [Route] = []
        var navigationRoutes: NavigationRoutes?
        
        for options in routeOptions {
            do {
                let request = mapboxNavigation.routingProvider().calculateRoutes(options: options)
                let result = await request.result
                
                switch result {
                case .success(let routes):
                    if navigationRoutes == nil {
                        navigationRoutes = routes
                    }
                    allRoutes.append(contentsOf: routes.allRoutes())
                case .failure(let error):
                    print("Error calculating route: \(error.localizedDescription)")
                }
            } catch {
                print("Error calculating route: \(error.localizedDescription)")
            }
        }
        
        guard !allRoutes.isEmpty, let navigationRoutes = navigationRoutes else {
            throw NavigationError.routeCalculationFailed
        }
        
        let analyzedRoutes = analyzeRoutes(allRoutes)
        
        // Log all routes for analysis
        for analyzedRoute in analyzedRoutes {
            print("DEBUG: Route - Time: \(analyzedRoute.route.expectedTravelTime), Distance: \(analyzedRoute.route.distance), Score: \(analyzedRoute.score)")
            print("DEBUG: Route - Turn Count: \(analyzedRoute.route.legs.flatMap { $0.steps }.count), Coordinate Count: \(analyzedRoute.route.shape?.coordinates.count ?? 0)")
        }
        
        // Select the route with the highest joyride score
        guard let selectedScoredRoute = analyzedRoutes.max(by: { $0.score < $1.score }) else {
            throw NavigationError.routeCalculationFailed
        }
        
        let selectedRoute = selectedScoredRoute.route
        print("DEBUG: Selected joyride route - Time: \(selectedRoute.expectedTravelTime), Distance: \(selectedRoute.distance), Score: \(selectedScoredRoute.score)")
        
        // Create a new NavigationRoutes object with the selected route
        let joyrideRoutes: NavigationRoutes
        if let originalRoute = allRoutes.first(where: { $0 == selectedRoute }),
           let index = allRoutes.firstIndex(of: originalRoute),
           index > 0 {
            joyrideRoutes = await navigationRoutes.selectingAlternativeRoute(at: index - 1) ?? navigationRoutes
        } else {
            joyrideRoutes = navigationRoutes
        }
        
        let navigationOptions = NavigationOptions(
            mapboxNavigation: mapboxNavigation,
            voiceController: mapboxNavigationProvider.routeVoiceController,
            eventsManager: mapboxNavigationProvider.eventsManager()
        )
        
        let navigationViewController = NavigationViewController(
            navigationRoutes: joyrideRoutes,
            navigationOptions: navigationOptions
        )
        navigationViewController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        
        // Set initial camera state
        let initialCameraOptions = CameraOptions(center: userLocation, zoom: 15, bearing: 0, pitch: 0)
        navigationViewController.navigationMapView?.mapView.camera.ease(
            to: initialCameraOptions,
            duration: 0,
            completion: nil as ((UIViewAnimatingPosition) -> Void)?
        )
        
        // Reset the flag after navigation has started
        if let gestureManagerDelegate = mapView.gestures.delegate as? MapManager {
            gestureManagerDelegate.isNavigationStarting = false
        }
        
        // Set the delegate
        navigationViewController.delegate = NavigationViewControllerDelegateImpl(navigationStateManager: navigationStateManager)
        
        // Configure the navigation view controller
        configureNavigationViewController(navigationViewController, userLocation: userLocation, routes: joyrideRoutes, styleURI: styleURI)
        
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
    }
    
    private static func createRouteOptions(origin: Waypoint, destination: Waypoint, profile: ProfileIdentifier) -> NavigationRouteOptions {
        let options = NavigationRouteOptions(waypoints: [origin, destination])
        options.includesAlternativeRoutes = true
        options.roadClassesToAvoid = [.motorway] // Avoid major highways for more interesting routes
        options.profileIdentifier = profile
        options.routeShapeResolution = .full
        options.attributeOptions = [.congestionLevel, .expectedTravelTime, .distance, .maximumSpeedLimit]
        options.includesSteps = true
        return options
    }
    
    
    private static func analyzeRoutes(_ routes: [Route]) -> [(route: Route, score: Double)] {
        return routes.map { route in
            let score = calculateJoyrideScore(route)
            return (route: route, score: score)
        }
    }
    
    private static func isDrivable(_ route: Route) -> Bool {
        // Check if the route has any steps with modes that are not suitable for driving
        return !route.legs.contains { leg in
            leg.steps.contains { step in
                step.transportType == .walking || step.transportType == .cycling
            }
        }
    }
    
    private static func calculateOverlapScore(_ drivingRoute: Route, _ avoidingTrafficRoutes: [Route]) -> Double {
        // Calculate how much a driving route overlaps with traffic-avoiding routes
        let drivingRoadNames = Set(drivingRoute.legs.flatMap { $0.steps }.compactMap { $0.names?.first })
        let avoidingTrafficRoadNames = Set(avoidingTrafficRoutes.flatMap { $0.legs.flatMap { $0.steps }.compactMap { $0.names?.first } })
        let sharedRoadNames = drivingRoadNames.intersection(avoidingTrafficRoadNames)
        return Double(sharedRoadNames.count) / Double(drivingRoadNames.count)
    }
    
    private static func calculateJoyrideScore(_ route: Route) -> Double {
        let steps = route.legs.flatMap { $0.steps }
        let roadNames = steps.compactMap { $0.names?.first }
        let uniqueRoadNames = Set(roadNames)
        
        // Calculate road change score (most important factor)
        let roadChanges = zip(roadNames, roadNames.dropFirst()).filter { $0 != $1 }.count
        let roadChangeScore = Double(roadChanges) / Double(steps.count)
        
        // Penalize staying on the same road for long stretches
        let maxStepsOnSameRoad = roadNames.reduce(into: (current: 0, max: 0)) { result, name in
            if result.1 == 0 || name != roadNames[result.1 - 1] {
                result.current = 1
            } else {
                result.current += 1
            }
            result.max = Swift.max(result.max, result.current)
        }.max
        let sameRoadPenalty = Double(maxStepsOnSameRoad) / Double(steps.count)
        
        // Calculate turn density
        let turnCount = steps.count
        let turnDensity = Double(turnCount) / (route.distance / 1000)
        let turnScore = min(1, turnDensity / 0.5)
        
        // Calculate road variety score
        let roadVarietyScore = Double(uniqueRoadNames.count) / Double(steps.count)
        
        // Penalize main roads more heavily
        let mainRoadKeywords = ["Highway", "Expressway", "Freeway", "Turnpike", "Parkway"]
        let mainRoadPenalty = steps.reduce(0.0) { penalty, step in
            if let roadName = step.names?.first, mainRoadKeywords.contains(where: { roadName.contains($0) }) {
                return penalty + 0.1
            }
            return penalty
        }
        
        // Combine scores (adjusted weights)
        let score = (roadChangeScore * 0.4 +
                     turnScore * 0.2 +
                     roadVarietyScore * 0.2) *
                    (1 - sameRoadPenalty) *
                    (1 - mainRoadPenalty)
        
        print("DEBUG: Route Score - Road Change Score: \(roadChangeScore), Turn Score: \(turnScore), Road Variety: \(roadVarietyScore), Same Road Penalty: \(sameRoadPenalty), Main Road Penalty: \(mainRoadPenalty), Total Score: \(score)")
        print("DEBUG: Route Details - Distance: \(route.distance), Time: \(route.expectedTravelTime), Turn Count: \(turnCount), Unique Road Names: \(uniqueRoadNames.count), Road Changes: \(roadChanges), Max Steps on Same Road: \(maxStepsOnSameRoad)")
        
        return score
    }

    private static func calculateCurvinessScore(_ route: Route) -> Double {
        guard let coordinates = route.shape?.coordinates else { return 0 }
        var totalAngleChange: Double = 0
        
        for i in 1..<coordinates.count - 1 {
            let prev = coordinates[i-1]
            let curr = coordinates[i]
            let next = coordinates[i+1]
            
            let angle1 = atan2(curr.latitude - prev.latitude, curr.longitude - prev.longitude)
            let angle2 = atan2(next.latitude - curr.latitude, next.longitude - curr.longitude)
            
            var angleDiff = abs(angle2 - angle1)
            if angleDiff > .pi {
                angleDiff = 2 * .pi - angleDiff
            }
            
            totalAngleChange += angleDiff
        }
        
        // Normalize the curviness (assuming pi/2 radians per km is maximum curviness)
        let normalizedCurviness = totalAngleChange / (route.distance / 1000) / (.pi / 2)
        return min(1, normalizedCurviness)
    }
    
    
    
    private static func longestStraightSegment(_ route: Route) -> Double {
        // Placeholder: Implement logic to find the longest straight segment in the route
        // This could involve analyzing the route geometry
        return 0
    }

    private static func configureNavigationViewController(_ navigationViewController: NavigationViewController, userLocation: CLLocationCoordinate2D, routes: NavigationRoutes, styleURI: String) {
        print("DEBUG: Configuring NavigationViewController")
        
        guard let navigationMapView = navigationViewController.navigationMapView else {
            print("DEBUG: NavigationMapView is nil")
            return
        }
        
        print("DEBUG: NavigationMapView frame: \(navigationMapView.frame)")
        print("DEBUG: NavigationMapView bounds: \(navigationMapView.bounds)")
        
        let initialCameraOptions = CameraOptions(center: userLocation, zoom: 15, bearing: 0, pitch: 0)
        navigationMapView.mapView.camera.ease(to: initialCameraOptions, duration: 0)
        print("DEBUG: Set initial camera position to: \(userLocation)")
        
        navigationMapView.viewportPadding = UIEdgeInsets(top: 20, left: 20, bottom: 40, right: 20)
        print("DEBUG: Set viewport padding: \(navigationMapView.viewportPadding)")
        
        navigationMapView.navigationCamera.viewportPadding = navigationMapView.viewportPadding
        print("DEBUG: Set navigation camera viewport padding")
        
        if let styleURI = StyleURI(rawValue: styleURI) {
            print("DEBUG: Loading style URI: \(styleURI.rawValue)")
            navigationMapView.mapView.mapboxMap.loadStyle(styleURI) { [weak navigationMapView] error in
                if let error = error {
                    print("DEBUG: Failed to load map style: \(error.localizedDescription)")
                } else {
                    print("DEBUG: Map style loaded successfully")
                    
                    navigationMapView?.mapView.camera.ease(to: initialCameraOptions, duration: 0)
                    print("DEBUG: Reset camera position after style load")
                    
                    navigationMapView?.showcase(
                        routes,
                        routesPresentationStyle: .all(),
                        animated: false,
                        duration: 0
                    )
                    print("DEBUG: Showcased routes")
                    
                    navigationMapView?.update(navigationCameraState: .following)
                    print("DEBUG: Updated camera state to following")
                }
            }
        } else {
            print("DEBUG: Invalid style URI: \(styleURI)")
        }

        navigationViewController.view.backgroundColor = .white
        print("DEBUG: Set NavigationViewController background color to white")

        navigationMapView.showsAlternatives = false
        navigationMapView.routeLineTracksTraversal = true
        navigationMapView.showsRestrictedAreasOnRoute = true
        print("DEBUG: Configured NavigationMapView settings")
        
        print("DEBUG: Initial camera state: \(navigationMapView.mapView.mapboxMap.cameraState)")
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
        return MKMapPoint(self).distance(to: MKMapPoint(other))
    }
}
