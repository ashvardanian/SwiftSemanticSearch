//
//  USearchMobileApp.swift
//  USearchMobile
//
//  Created by Ashot Vardanian on 7/23/23.
//

import SwiftUI
import MapKit

import USearch

class SearchManager: ObservableObject {
    @Published var annotations: [MKPointAnnotation] = []
    @Published var title: String = ""
    var index: USearchIndex
    var points: [[Float32]]

    init() {
        index = USearchIndex.make(metric: .IP, dimensions: 2, connectivity: 16, quantization: .F32)
        points = []
        setupSearchIndex()
    }
    
    func setupSearchIndex() {
        index = USearchIndex.make(metric: .haversine, dimensions: 2, connectivity: 16, quantization: .F32)
        let _ = index.reserve(1000)
        
        // Center point in Yerevan, Armenia
        points = (0..<1000).map { _ in
            [40.18306093751397 + Float32.random(in: -0.5...0.5), 44.52643090940268 + Float32.random(in: -0.5...0.5)]
        }
        points.enumerated().forEach { i, coordinates in
            let _ = index.add(key: USearchKey(i), vector: coordinates)
        }
    }
    
    func recomputeSearchResults(center: CLLocationCoordinate2D, visibleMapRect: MKMapRect) {
        let neMapPoint = MKMapPoint(x: visibleMapRect.maxX, y: visibleMapRect.minY)
        let swMapPoint = MKMapPoint(x: visibleMapRect.minX, y: visibleMapRect.maxY)
        let neCoord = neMapPoint.coordinate
        let swCoord = swMapPoint.coordinate
        let latRange = min(swCoord.latitude, neCoord.latitude)...max(swCoord.latitude, neCoord.latitude)
        let lonRange = min(swCoord.longitude, neCoord.longitude)...max(swCoord.longitude, neCoord.longitude)
        
        let results = index.search(vector: [center.latitude, center.longitude], count: 5)
        annotations = results.0.filter({ (key: USearchKey) in
            let coordinates = points[Int(key)]
            return latRange.contains(CLLocationDegrees(coordinates[0])) && lonRange.contains(CLLocationDegrees(coordinates[1]))
        }).map { (key: USearchKey) in
            let coordinates = points[Int(key)]
            let annotation = MKPointAnnotation()
            annotation.title = String(key)
            annotation.coordinate = CLLocationCoordinate2D(latitude: CLLocationDegrees(coordinates[0]), longitude: CLLocationDegrees(coordinates[1]))
            return annotation
        }
        title = "Showing \(annotations.count) / \(index.length) points"
    }
}

struct MapView: UIViewRepresentable {
    var annotations: [MKPointAnnotation]
    var onRegionChange: (MKMapRect) -> Void
    @Binding var centerCoordinate: CLLocationCoordinate2D
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.addAnnotations(annotations)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.centerCoordinate = mapView.centerCoordinate
            parent.onRegionChange(mapView.visibleMapRect)
        }
    }
}


@main
struct USearchMobileApp: App {
    @StateObject var searchManager = SearchManager()
    @State private var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 40.18306093751397, longitude: 44.52643090940268)
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                MapView(annotations: searchManager.annotations, onRegionChange: { visibleMapRect in
                    DispatchQueue.main.async {
                        searchManager.recomputeSearchResults(center: centerCoordinate, visibleMapRect: visibleMapRect)
                    }
                }, centerCoordinate: $centerCoordinate)
                .edgesIgnoringSafeArea(.all)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading:
                    Text(searchManager.title)
                    .font(.headline)  // Make it bold
                    .frame(maxWidth: .infinity, alignment: .center)  // Align horizontally
                )
            }
        }
    }
}
