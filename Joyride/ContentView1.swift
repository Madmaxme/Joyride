//
//  ContentView1.swift
//  Joyride
//
//  Created by CodingGuru on 8/15/24.
//

import SwiftUI
import CoreLocation
import MapboxNavigationCore
import MapboxDirections
import MapboxNavigationUIKit

struct ContentView1: View {
    @StateObject private var viewModel = MapViewModel()
    @State private var startCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco
    @State private var destinationCoordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437) // Los Angeles
    
    var body: some View {
        VStack {
            MapboxView(route: $viewModel.route)
                .edgesIgnoringSafeArea(.all)
            
            HStack {
                Button(action: {
                    viewModel.calculateAndDisplayRoute(from: startCoordinate, to: destinationCoordinate)
                }) {
                    Text("Calculate Route")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                if viewModel.route != nil {
                    Button(action: {
                        startNavigation()
                    }) {
                        Text("Start Navigation")
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
    }
    
    func startNavigation() {
        guard let route = viewModel.route else { return }
        let navigationService = MapboxNavigationService(route: route)
       
        let navigationOptions = NavigationOptions(navigationService: navigationService)
        let viewController = NavigationViewController(for: route, options: navigationOptions)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.first?.rootViewController?.present(viewController, animated: true, completion: nil)
        }
    }
}
