import MapboxMaps
import CoreLocation
import MapboxSearch
import UIKit

class MapManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var mapView: MapView?
    @Published var currentStyleIndex = 0
    @Published var annotationsAdded = false
    @Published var isUserPanning = false
    var isNavigationStarting: Bool = false
    private var locationManager: CLLocationManager?
    private let styles: [StyleURI] = [.streets, .outdoors, .light, .dark, .satellite, .satelliteStreets]
    private var pointAnnotationManager: PointAnnotationManager?
    private var tapGestureRecognizer: UITapGestureRecognizer?
    weak var searchManager: SearchManager?
    @Published var initialLocationSet = false
    private var lastCameraUpdateTime: Date = Date.distantPast
    let navigationStateManager: NavigationStateManager

    init(navigationStateManager: NavigationStateManager) {
        self.navigationStateManager = navigationStateManager
        super.init()
        setupLocationManager()
        print("DEBUG: MapManager initialized")
    }
    
    func setupMapView() {
        guard mapView == nil else {
            print("DEBUG: MapView already exists, skipping setup")
            return
        }
        mapView = MapManager.createMapView()
        mapView?.frame = UIScreen.main.bounds
        print("DEBUG: Map view created with frame: \(mapView?.frame ?? .zero)")
        print("DEBUG: Map view bounds: \(mapView?.bounds ?? .zero)")
        mapView?.gestures.delegate = self
        print("DEBUG: Gesture delegate set to MapManager")
        setupTapGestureRecognizer()
        
        mapView?.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            guard let self = self else {
                print("DEBUG: Self is nil in style loaded callback")
                return
            }
            self.pointAnnotationManager = self.mapView?.annotations.makePointAnnotationManager()
            print("DEBUG: PointAnnotationManager created: \(self.pointAnnotationManager != nil)")
            self.centerOnUserLocation()
            print("DEBUG: Map style loaded and gesture recognizers set up")
        }

        locationManager?.startUpdatingLocation()
        print("DEBUG: Started updating location")
    }

    func setupTapGestureRecognizer() {
        if tapGestureRecognizer == nil {
            tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
            tapGestureRecognizer?.numberOfTapsRequired = 1
            tapGestureRecognizer?.numberOfTouchesRequired = 1
            mapView?.addGestureRecognizer(tapGestureRecognizer!)
            print("DEBUG: Tap gesture recognizer added to map view")
        }
    }
    
    static func createMapView() -> MapView {
        let mapInitOptions = MapInitOptions(styleURI: .streets)
        let mapView = MapView(frame: UIScreen.main.bounds, mapInitOptions: mapInitOptions)
        mapView.location.options.puckType = .puck2D()
        return mapView
    }
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager?.distanceFilter = 10
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
    }
    
    func centerMapOn(coordinate: CLLocationCoordinate2D, zoom: Double = 14) {
        let cameraOptions = CameraOptions(center: coordinate, zoom: zoom)
        mapView?.camera.ease(to: cameraOptions, duration: 0.5)
        lastCameraUpdateTime = Date()
    }
    
    func centerOnUserLocation() {
        if let userLocation = locationManager?.location?.coordinate {
            centerMapOn(coordinate: userLocation, zoom: 14)
            isUserPanning = false
        } else {
            locationManager?.requestLocation()
        }
    }
    
    func cycleMapStyle() {
        currentStyleIndex = (currentStyleIndex + 1) % styles.count
        mapView?.mapboxMap.styleURI = styles[currentStyleIndex]
    }
    
    func addAnnotations(for results: [SearchResult]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("DEBUG: Starting to add annotations for \(results.count) results")
            
            if self.pointAnnotationManager == nil {
                print("DEBUG: PointAnnotationManager is nil, initializing...")
                self.pointAnnotationManager = self.mapView?.annotations.makePointAnnotationManager()
            }
            
            self.pointAnnotationManager?.annotations = []
            
            var pointAnnotations: [PointAnnotation] = []
            
            for (index, result) in results.enumerated() {
                var annotation = PointAnnotation(coordinate: result.coordinate)
                
                let imageSize = CGSize(width: 24, height: 24)
                UIGraphicsBeginImageContextWithOptions(imageSize, false, UIScreen.main.scale)
                let context = UIGraphicsGetCurrentContext()!

                let circlePath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 24, height: 24))
                UIColor.systemBlue.setFill()
                circlePath.fill()

                UIColor.white.setStroke()
                circlePath.lineWidth = 2
                circlePath.stroke()

                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()

                if let image = image {
                    annotation.image = .init(image: image, name: "marker-icon-\(index)")
                }

                annotation.iconAnchor = .center
                annotation.iconOffset = [0, 0]
                
                annotation.textField = result.name
                annotation.textOffset = [0, 1.6]
                annotation.textColor = StyleColor(.darkGray)
                annotation.textHaloColor = StyleColor(.white)
                annotation.textHaloWidth = 2.0
                annotation.textSize = 12
                annotation.textAnchor = .top
                
                var jsonObject = JSONObject()
                jsonObject["name"] = .string(result.name)
                jsonObject["latitude"] = .number(Double(result.coordinate.latitude))
                jsonObject["longitude"] = .number(Double(result.coordinate.longitude))
                annotation.customData = jsonObject

                pointAnnotations.append(annotation)
                print("DEBUG: Created annotation for \(result.name) at \(result.coordinate)")
            }
            
            self.pointAnnotationManager?.annotations = pointAnnotations
            
            print("DEBUG: Set \(pointAnnotations.count) annotations")
            print("DEBUG: Total annotations after adding: \(self.pointAnnotationManager?.annotations.count ?? 0)")
            
            self.annotationsAdded = true
            
            if let bounds = self.coordinateBounds(for: results.map { $0.coordinate }) {
                print("DEBUG: Setting camera to bounds: \(bounds)")
                self.setCameraToBounds(bounds, padding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50))
            }
        }
    }
    
    func coordinateBounds(for coordinates: [CLLocationCoordinate2D]) -> CoordinateBounds? {
        guard !coordinates.isEmpty else { return nil }
        
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        
        let southwest = CLLocationCoordinate2D(latitude: latitudes.min()!, longitude: longitudes.min()!)
        let northeast = CLLocationCoordinate2D(latitude: latitudes.max()!, longitude: longitudes.max()!)
        
        return CoordinateBounds(southwest: southwest, northeast: northeast)
    }
    
    func setCameraToBounds(_ bounds: CoordinateBounds, padding: UIEdgeInsets) {
        let southwest = bounds.southwest
        let northeast = bounds.northeast
        let coordinates = [
            CLLocationCoordinate2D(latitude: southwest.latitude, longitude: southwest.longitude),
            CLLocationCoordinate2D(latitude: northeast.latitude, longitude: northeast.longitude)
        ]
        
        let camera = mapView?.mapboxMap.camera(
            for: coordinates,
            padding: padding,
            bearing: nil,
            pitch: nil
        )
        mapView?.camera.ease(to: camera!, duration: 1.0)
    }
    
    @objc private func handleMapTap(_ gesture: UITapGestureRecognizer) {
        print("DEBUG: handleMapTap called")
        let point = gesture.location(in: mapView)
        print("DEBUG: Tap detected at point: \(point)")
        
        guard let mapView = self.mapView,
              let styleURI = mapView.mapboxMap.styleURI?.rawValue else {
            print("DEBUG: MapView or styleURI not available")
            return
        }
        
        mapView.mapboxMap.queryRenderedFeatures(
            with: point,
            options: RenderedQueryOptions(layerIds: nil, filter: nil)
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let features):
                print("DEBUG: Found \(features.count) features at tapped location")
                if let firstFeature = features.first,
                   let properties = firstFeature.queriedFeature.feature.properties,
                   let customData = properties["custom_data"] as? JSONValue {
                    
                    print("DEBUG: Attempting to extract custom data")
                    print("DEBUG: Raw custom data: \(customData)")
                    
                    let name: String = {
                        if case .object(let obj) = customData,
                           case .string(let str)? = obj["name"] {
                            return str
                        }
                        return "Unknown"
                    }()
                    
                    let latitude: Double = {
                        if case .object(let obj) = customData,
                           case .number(let num)? = obj["latitude"] {
                            return num
                        }
                        return 0
                    }()
                    
                    let longitude: Double = {
                        if case .object(let obj) = customData,
                           case .number(let num)? = obj["longitude"] {
                            return num
                        }
                        return 0
                    }()
                    
                    print("DEBUG: Extracted data - name: \(name), lat: \(latitude), lon: \(longitude)")
                    
                    if name != "Unknown" && latitude != 0 && longitude != 0 {
                        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                        
                        // Stop any ongoing camera animations
                        mapView.camera.cancelAnimations()
                        
                        Task {
                            do {
                                print("DEBUG: Calling NavigationManager.startNavigation")
                                try await NavigationManager.startNavigation(
                                    to: coordinate,
                                    name: name,
                                    mapView: mapView,
                                    styleURI: styleURI,
                                    navigationStateManager: self.navigationStateManager
                                )
                                print("DEBUG: Navigation started successfully")
                            } catch {
                                print("DEBUG: Failed to start navigation: \(error)")
                            }
                        }
                    } else {
                        print("DEBUG: Invalid data extracted, not starting navigation")
                    }
                } else {
                    print("DEBUG: Failed to extract required data")
                    print("DEBUG: Properties: \(String(describing: features.first?.queriedFeature.feature.properties))")
                    if let customData = features.first?.queriedFeature.feature.properties?["custom_data"] {
                        print("DEBUG: Custom data: \(String(describing: customData))")
                        print("DEBUG: Custom data type: \(type(of: customData))")
                    }
                }
            case .failure(let error):
                print("DEBUG: Failed to query rendered features: \(error)")
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            print("DEBUG: No locations in update")
            return
        }
        
        if isNavigationStarting {
            print("DEBUG: Location update skipped. isNavigationStarting: \(isNavigationStarting)")
            return
        }
        
        print("DEBUG: Location updated to \(location.coordinate)")
        
        let currentTime = Date()
        if !initialLocationSet {
            centerMapOn(coordinate: location.coordinate, zoom: 14)
            initialLocationSet = true
            print("DEBUG: Initial location set: \(location.coordinate)")
        } else if !isUserPanning && currentTime.timeIntervalSince(lastCameraUpdateTime) > 2 {
            mapView?.camera.ease(
                to: CameraOptions(center: location.coordinate, zoom: mapView?.mapboxMap.cameraState.zoom),
                duration: 0.5
            )
            lastCameraUpdateTime = currentTime
            print("DEBUG: Camera updated to new location: \(location.coordinate)")
        }
        
        print("DEBUG: Location updated - isUserPanning: \(isUserPanning)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("DEBUG: Location manager error: \(error.localizedDescription)")
        if let clError = error as? CLError {
            print("DEBUG: CLError code: \(clError.code.rawValue)")
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            locationManager?.startUpdatingLocation()
        }
    }
}

extension MapManager: GestureManagerDelegate {
    func gestureManager(_ gestureManager: GestureManager, didBegin gestureType: GestureType) {
        if gestureType == .pan || gestureType == .pinch {
            isUserPanning = true
            print("DEBUG: User started panning/pinching")
        }
    }
    
    func gestureManager(_ gestureManager: GestureManager, didEnd gestureType: GestureType, willAnimate: Bool) {
        print("DEBUG: Gesture ended - type: \(gestureType), willAnimate: \(willAnimate)")
    }
    
    func gestureManager(_ gestureManager: GestureManager, didEndAnimatingFor gestureType: GestureType) {
        print("DEBUG: Gesture animation ended - type: \(gestureType)")
    }
}
