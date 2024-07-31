//
//  SearchManager.swift
//  Joyride
//
//  Created by Maximillian Ludwick on 7/23/24.
//

import SwiftUI
import MapboxMaps
import MapboxSearch
import MapboxSearchUI
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit

class SearchManager: NSObject, ObservableObject, SearchControllerDelegate {
    @Published var isVisible = false
    @Published var styleIndex: Int = 0
    @Published var selectedResult: SearchResult?
    weak var mapManager: MapManager?
    var styles: [StyleURI]
    weak var searchController: MapboxSearchController?
    let categorySearchEngine = CategorySearchEngine()
    let navigationStateManager: NavigationStateManager

    init(mapManager: MapManager, styles: [StyleURI], navigationStateManager: NavigationStateManager) {
        self.mapManager = mapManager
        self.styles = styles
        self.navigationStateManager = navigationStateManager
        super.init()
    }
    
    
    func searchResultSelected(_ searchResult: SearchResult) {
        let coordinate = searchResult.coordinate
        
        Task {
            do {
                guard let mapView = mapManager?.mapView,
                      let userLocation = try? await NavigationManager.getUserLocation(mapView: mapView) else {
                    print("DEBUG: User location not available")
                    await MainActor.run {
                        showErrorAlert(message: "Unable to determine your location. Please try again.")
                    }
                    return
                }
                
                // Stop any ongoing camera animations
                await MainActor.run {
                    mapManager?.mapView?.camera.cancelAnimations()
                }
                
                try await NavigationManager.startNavigation(
                    to: coordinate,
                    name: searchResult.name,
                    mapView: mapView,
                    styleURI: styles[mapManager?.currentStyleIndex ?? 0].rawValue,
                    navigationStateManager: self.navigationStateManager
                )
                print("DEBUG: Navigation started successfully from SearchManager")
            } catch {
                print("DEBUG: Failed to start navigation from SearchManager: \(error)")
                await MainActor.run {
                    showErrorAlert(message: "Failed to start navigation: \(error.localizedDescription)")
                }
            }
        }
    }
        
    func categorySearchResultsReceived(category: SearchCategory, results: [SearchResult]) {
        print("Received \(results.count) results for category: \(category.name)")
        
        DispatchQueue.main.async {
            self.isVisible = false
            self.mapManager?.addAnnotations(for: results)
            
            if let bounds = self.mapManager?.coordinateBounds(for: results.map { $0.coordinate }) {
                let padding = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
                self.mapManager?.setCameraToBounds(bounds, padding: padding)
            }
        }
    }
        
    func userFavoriteSelected(_ userFavorite: FavoriteRecord) {
        let coordinate = userFavorite.coordinate
        mapManager?.centerMapOn(coordinate: coordinate, zoom: 14)
    }

    func updateStyleIndex(_ newIndex: Int) {
        self.styleIndex = newIndex
    }
    
    func shouldCollapseForSelection(_ searchResult: SearchResult) -> Bool {
        return true
    }
    
    private func showErrorAlert(message: String) {
        print("ERROR: \(message)")
        // Implement a proper alert here, e.g., using UIAlertController
    }
}
