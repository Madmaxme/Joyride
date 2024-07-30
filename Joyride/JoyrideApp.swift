//
//  JoyrideApp.swift
//  Joyride
//
//  Created by Maximillian Ludwick on 7/21/24.
//

import SwiftUI
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit
import MapboxMaps

@main
struct JoyrideApp: App {
    @StateObject private var navigationStateManager = NavigationStateManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView(navigationStateManager: navigationStateManager)
        }
    }
}

class NavigationStateManager: ObservableObject {
    @Published var isNavigating: Bool = false
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleBackgroundNotification), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleForegroundNotification), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc func handleBackgroundNotification() {
        if isNavigating {
            // Handle background state if needed
            print("App entered background while navigating")
        }
    }
    
    @objc func handleForegroundNotification() {
        if isNavigating {
            // Handle foreground state if needed
            print("App entered foreground while navigating")
        }
    }
}
