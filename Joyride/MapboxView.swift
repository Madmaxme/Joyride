//
//  MapboxView.swift
//  Joyride
//
//  Created by CodingGuru on 8/18/24.
//

import SwiftUI
import MapboxMaps
import MapboxDirections
import MapboxNavigationCore

struct MapboxView: UIViewRepresentable {
    @Binding var route: Route?
    
    func makeUIView(context: Context) -> NavigationMapView {
        let mapView = NavigationMapView(location: AnyPublisher<CLLocation, Never>, routeProgress: AnyPublisher<RouteProgress?, Never>)
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: NavigationMapView, context: Context) {
        uiView.removeRoutes()
        
        if let route = route {
            uiView.show(NavigationRoutes, routeAnnotationKinds: Set<RouteAnnotationKind>)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NavigationMapViewDelegate {
        var parent: MapboxView
        
        init(_ parent: MapboxView) {
            self.parent = parent
        }
    }
}
