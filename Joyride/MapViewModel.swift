//
//  MapViewModel.swift
//  Joyride
//
//  Created by CodingGuru on 8/15/24.
//

import SwiftUI
import MapboxDirections
import MapboxNavigationCore
import MapKit

class MapViewModel: ObservableObject {
    @Published var route: Route?
    
    func calculateAndDisplayRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        let originWaypoint = Waypoint(coordinate: origin, coordinateAccuracy: -1, name: "Start")
        let destinationWaypoint = Waypoint(coordinate: destination, coordinateAccuracy: -1, name: "Destination")
        
        let options = NavigationRouteOptions(waypoints: [originWaypoint, destinationWaypoint], profileIdentifier: .automobileAvoidingTraffic)
        
        options.roadClassesToAvoid = .init(arrayLiteral: .toll, .ferry)
        
        Directions.shared.calculate(options) { (result) in
            switch result {
                case .failure(let error):
                    print("Error calculating directions: \(error.localizedDescription)")
                case .success(let response):
                    guard let routes = response.routes else { return }
                    self.route = self.selectBestRoute(routes: routes)
            }
        }
    }
    
    func selectBestRoute(routes: [Route]) -> Route {
        var bestRoute: Route = routes.first!
        var bestScore: Double = -Double.infinity
        
        for route in routes {
            let score = calculateScore(for: route)
            if score > bestScore {
                bestRoute = route
                bestScore = score
            }
        }
        
        return bestRoute
    }
    
    func calculateScore(for route: Route) -> Double {
        var score: Double = 0
        
        for leg in route.legs {
            for step in leg.steps {
                if let roadClass = step.intersections?.first?.outletRoadClasses {
                    if roadClass.contains(.motorway) {
                        score -= 1 // Penalize highways
                    } else if roadClass.contains(.toll) || roadClass.contains(.tunnel) || roadClass.contains(.highOccupancyToll) || roadClass.contains(.highOccupancyVehicle2) || roadClass.contains(.highOccupancyVehicle3) {
                        score += 1.5 // Reward secondary and tertiary roads
                    }
                }
                
                if step.distance > 1000 { // Example condition for longer, more scenic roads
                    score += 0.5
                }
            }
        }
        
        return score
    }
}
