import SwiftUI
import MapboxMaps
import CoreLocation

struct MutedMapView: UIViewRepresentable {
    let styleURL: String
    var coordinate: CLLocationCoordinate2D?

    // Helper to truncate to 4 decimal places
    private func truncatedCoordinate(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        func truncate(_ value: CLLocationDegrees) -> CLLocationDegrees {
            Double(String(format: "%.4f", value)) ?? value
        }
        return CLLocationCoordinate2D(latitude: truncate(coord.latitude), longitude: truncate(coord.longitude))
    }

    func makeUIView(context: Context) -> MapView {
        let mapInitOptions = MapInitOptions(styleURI: StyleURI(url: URL(string: styleURL)!))
        let mapView = MapView(frame: .zero, mapInitOptions: mapInitOptions)

        // Hide Mapbox logo/attribution if desired (check Mapbox TOS)
        mapView.ornaments.logoView.isHidden = true
        mapView.ornaments.attributionButton.isHidden = true

        // Remove the user's location puck (do not show it)
        mapView.location.options.puckType = nil
        mapView.location.options.puckBearingEnabled = false

        // Initial camera position with 10-second cooldown
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if let coordinate = coordinate {
                let truncated = truncatedCoordinate(coordinate)
                let lat = truncated.latitude
                let lon = truncated.longitude
                print("MutedMapView using lat: \(lat), lon: \(lon)")
                mapView.camera.ease(
                    to: CameraOptions(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), zoom: 3.5),
                    duration: 0.0
                )
            } else {
                // Fallback to US
                let lat = 39.8283
                let lon = -98.5795
                mapView.camera.ease(
                    to: CameraOptions(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), zoom: 3.5),
                    duration: 0.0
                )
            }
        }

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        // Camera update with 10-second cooldown
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if let coordinate = coordinate {
                let truncated = truncatedCoordinate(coordinate)
                let lat = truncated.latitude
                let lon = truncated.longitude
                print("MutedMapView using lat: \(lat), lon: \(lon)")
                uiView.camera.ease(
                    to: CameraOptions(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), zoom: 3.5),
                    duration: 0.5
                )
            }
        }
    }
}

struct MutedMapViewContainer: View {
    let styleURL: String
    var coordinate: CLLocationCoordinate2D?
    @Binding var currentPage: AppPage
    @State private var animatePulse = false
    @State private var animateBlackCircle = false
    @AppStorage("showMutedLocationIndicator") private var showMutedLocationIndicator: Bool = false
    @State private var showActivityIndicator: Bool = true
    var body: some View {
        ZStack {
            MutedMapView(styleURL: styleURL, coordinate: coordinate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 15/255.0, green: 15/255.0, blue: 25/255.0))
                .ignoresSafeArea()
                .scaleEffect(1.5)
            ZStack {
                // Animated pulsing circle (only if toggle is on)
                if showMutedLocationIndicator {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 100, height: 100)
                        .scaleEffect(animatePulse ? 1.0 : 0.0)
                        .opacity(animatePulse ? 0.0 : 0.4)
                        .animation(Animation.easeOut(duration: 3).repeatForever(autoreverses: false), value: animatePulse)
                    if animatePulse {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                            .opacity(1.0)
                    }
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 30, height: 30)
                            .scaleEffect(animateBlackCircle ? (20.0/30.0) : 1.0)
                            .animation(Animation.easeOut(duration: 0.5), value: animateBlackCircle)
                            .opacity(1.0)
                        ActivityIndicator(isAnimating: .constant(!animatePulse))
                            .frame(width: 18, height: 18)
                            .opacity((!animatePulse && showMutedLocationIndicator && currentPage != .speedDetail && showActivityIndicator) ? 1.0 : 0.0)
                            .animation(.easeOut(duration: 0.5), value: animatePulse)
                    }
                } else {
                    // Only show the activity indicator centered when toggle is off (no black circle)
                    ActivityIndicator(isAnimating: .constant(true))
                        .frame(width: 18, height: 18)
                        .opacity((!showMutedLocationIndicator && currentPage != .speedDetail && showActivityIndicator) ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.5), value: showMutedLocationIndicator)
                }
            }
            .opacity(currentPage != .speedDetail ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.5), value: showMutedLocationIndicator)
        }
        .onAppear {
            animatePulse = false
            animateBlackCircle = false
            showActivityIndicator = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                animatePulse = true
                animateBlackCircle = true
                withAnimation(.easeOut(duration: 0.5)) {
                    showActivityIndicator = false
                }
            }
        }
    }

    private func startPulseAnimation() {
        animatePulse = false
        animateBlackCircle = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            animatePulse = true
            animateBlackCircle = true
        }
    }
}

// ActivityIndicator UIViewRepresentable
struct ActivityIndicator: UIViewRepresentable {
    @Binding var isAnimating: Bool
    let style: UIActivityIndicatorView.Style = .medium

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView(style: style)
        indicator.hidesWhenStopped = true
        return indicator
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
} 

