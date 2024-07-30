//
//  ContentView.swift
//  Joyride
//
//  Created by Maximillian Ludwick on 7/21/24.
//
import SwiftUI
import MapboxMaps
import MapboxSearch
import MapboxSearchUI

struct ContentView: View {
    @StateObject private var mapManager: MapManager
    @StateObject private var searchManager: SearchManager
    @State private var mapNeedsUpdate = false
    @ObservedObject var navigationStateManager: NavigationStateManager
    
    private let styles = [
        StyleURI.streets,
        StyleURI.outdoors,
        StyleURI.light,
        StyleURI.dark,
        StyleURI.satellite,
        StyleURI.satelliteStreets
    ]
    
    init(navigationStateManager: NavigationStateManager) {
        self.navigationStateManager = navigationStateManager
        let mapManager = MapManager(navigationStateManager: navigationStateManager)
        let searchManager = SearchManager(mapManager: mapManager, styles: styles, navigationStateManager: navigationStateManager)
        _mapManager = StateObject(wrappedValue: mapManager)
        _searchManager = StateObject(wrappedValue: searchManager)
    }
    
    var body: some View {
        ZStack {
            MapViewRepresentable(mapView: $mapManager.mapView, mapNeedsUpdate: $mapNeedsUpdate, mapManager: mapManager)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                if !searchManager.isVisible {
                    searchButton
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    VStack {
                        styleButton
                        UserLocationButton {
                            mapManager.centerOnUserLocation()
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            
            if searchManager.isVisible {
                MapboxSearchViewRepresentable(isVisible: $searchManager.isVisible, searchManager: searchManager)
                    .transition(.move(edge: .top))
            }
        }
        .onAppear {
            mapManager.setupMapView()
        }
        .onChange(of: mapManager.annotationsAdded) { _ in
            DispatchQueue.main.async {
                mapNeedsUpdate = true
            }
        }
    }
    
    private var searchButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                searchManager.isVisible = true
            }
        }) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .padding(10)
                .background(Color.white.opacity(0.8))
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .padding(.top, 50)
    }
    
    private var styleButton: some View {
        Button(action: {
            mapManager.cycleMapStyle()
            searchManager.updateStyleIndex(mapManager.currentStyleIndex)
        }) {
            Image(systemName: "paintbrush")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .padding(10)
                .background(Color.white.opacity(0.8))
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 8)
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var mapView: MapView?
    @Binding var mapNeedsUpdate: Bool
    var mapManager: MapManager
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapManager.createMapView()
        mapView.frame = UIScreen.main.bounds
        self.mapManager.mapView = mapView
        self.mapManager.setupTapGestureRecognizer()
        return mapView
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
        if mapNeedsUpdate {
            uiView.mapboxMap.loadStyle(uiView.mapboxMap.style.styleURI!.rawValue) { _ in
                print("Map style reloaded")
            }
            mapNeedsUpdate = false
        }
    }
}

struct MapboxSearchViewRepresentable: UIViewControllerRepresentable {
    @Binding var isVisible: Bool
    @ObservedObject var searchManager: SearchManager

    func makeUIViewController(context: Context) -> MapboxPanelController {
        let searchController = MapboxSearchController()
        searchController.searchBarPlaceholder = "Search for a place or category"
        searchController.delegate = searchManager
        searchManager.searchController = searchController
        
        searchController.categorySearchEngine = searchManager.categorySearchEngine
        
        let panelController = MapboxPanelController(rootViewController: searchController)
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panelController.view.addGestureRecognizer(panGesture)
        
        return panelController
    }

    func updateUIViewController(_ uiViewController: MapboxPanelController, context: Context) {
        uiViewController.setState(isVisible ? .opened : .collapsed, animated: true)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MapboxSearchViewRepresentable
        
        init(_ parent: MapboxSearchViewRepresentable) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            switch gesture.state {
            case .changed:
                if translation.y > 0 {
                    gesture.view?.transform = CGAffineTransform(translationX: 0, y: translation.y)
                }
            case .ended:
                if velocity.y > 500 || translation.y > 200 {
                    parent.isVisible = false
                } else {
                    UIView.animate(withDuration: 0.3) {
                        gesture.view?.transform = .identity
                    }
                }
            default:
                break
            }
        }
    }
}

struct UserLocationButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
    }
}
