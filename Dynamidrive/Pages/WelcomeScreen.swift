import SwiftUI
import MapKit
import CoreLocation
import WebKit

class LocationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.334_900, longitude: -122.009_020),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    
    private let locationManager = CLLocationManager()
    @Published var locationStatus: CLAuthorizationStatus?
    var onPermissionGranted: (() -> Void)?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            onPermissionGranted?()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        withAnimation {
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }
        
        // Stop updating after we get the initial location
        locationManager.stopUpdatingLocation()
    }
}

struct WelcomeScreen: View {
    @Binding var isPresented: Bool
    @StateObject private var locationViewModel = LocationViewModel()
    @AppStorage("hasSeenWelcomeScreen") private var hasSeenWelcomeScreen = false
    @AppStorage("hasGrantedLocationPermission") private var hasGrantedLocationPermission = false
    @AppStorage("mapStyle") private var mapStyle: MapStyle = .standard
    @AppStorage("backgroundType") private var backgroundType: BackgroundType = .map
    @AppStorage("locationTrackingEnabled") private var locationTrackingEnabled: Bool = true

    @AppStorage("gradientStartRed") private var gradientStartRed: Double = 0
    @AppStorage("gradientStartGreen") private var gradientStartGreen: Double = 122/255
    @AppStorage("gradientStartBlue") private var gradientStartBlue: Double = 1.0
    @AppStorage("gradientEndRed") private var gradientEndRed: Double = 88/255
    @AppStorage("gradientEndGreen") private var gradientEndGreen: Double = 86/255
    @AppStorage("gradientEndBlue") private var gradientEndBlue: Double = 214/255

    var gradientStartColor: Color {
#if os(macOS)
        Color(NSColor(red: gradientStartRed, green: gradientStartGreen, blue: gradientStartBlue, alpha: 1))
#else
        Color(UIColor(red: CGFloat(gradientStartRed), green: CGFloat(gradientStartGreen), blue: CGFloat(gradientStartBlue), alpha: 1))
#endif
    }
    
    var gradientEndColor: Color {
#if os(macOS)
        Color(NSColor(red: gradientEndRed, green: gradientEndGreen, blue: gradientEndBlue, alpha: 1))
#else
        Color(UIColor(red: CGFloat(gradientEndRed), green: CGFloat(gradientEndGreen), blue: CGFloat(gradientEndBlue), alpha: 1))
#endif
    }
    
    @State private var showMapSettings = false
    @State private var showTrackingSettings = false
    @State private var mapSettingsHidden = false
    @State private var showAIMode = false
    @State private var aiModeHidden = false
    @State private var secondPhaseHidden = false
    
    @State private var showSixthSection = false
    @State private var sixthSectionHidden = false
    
    @State private var aiGradientRotation: Double = 0
    private let aiGradientTimer = Timer.publish(every: 0.015, on: .main, in: .common).autoconnect()
    
    @State private var showPrivacyPolicy = false

    enum MapStyle: String {
        case standard
        case satellite
    }
    
    enum BackgroundType: String, Codable {
        case map
        case gradient
    }
    
    private let welcomeMessages = [
        "Welcome to",
        "Thanks for installing",
        "Introducing",
        "Get ready to experience",
        "Meet"
    ]
    
    @State private var selectedMessage: String
    @State private var showingSecondPhase = false
    @State private var slideContent = false
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._selectedMessage = State(initialValue: welcomeMessages.randomElement() ?? "Welcome to")
    }
    
    var body: some View {
        ZStack {
            // Initial content
            VStack {
                Text(selectedMessage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.gray)
                    .padding(.top, 40)
                
                Text("Dynamidrive")
                    .font(.custom("PPNeueMachina-Ultrabold", size: 45))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .white,
                                Color(red: 1, green: 1, blue: 1, opacity: 0.392)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .padding(.top, 5)
                
                Spacer().frame(height: 110)
                
                Image("LiquidGlassIconDark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                
                Spacer()
            }
            .offset(x: showMapSettings ? -UIScreen.main.bounds.width * 2 : (slideContent ? -UIScreen.main.bounds.width * 2 : 0))
            
            // New content sliding in
            if showingSecondPhase && !secondPhaseHidden {
                VStack(spacing: 20) {
                    Text("First thing's first")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                    
                    Spacer()
                    
                    Text("We really need your location for the app to work. Please select \"Allow while using app\" then \"Change to Always Allow\" so the music can update in the background.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 1)
                        .ignoresSafeArea()
                }
                .offset(x: (showMapSettings || showTrackingSettings) ? -UIScreen.main.bounds.width : (slideContent ? 0 : UIScreen.main.bounds.width))
                .onAppear {
                    locationViewModel.onPermissionGranted = {
                        hasGrantedLocationPermission = true
                        withAnimation(.easeInOut(duration: 0.6)) {
                            showMapSettings = true
                        }
                        hasSeenWelcomeScreen = true
                    }
                    locationViewModel.requestPermission()
                }
            }
            
            // Map Settings Section
            if showMapSettings && !mapSettingsHidden {
                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 90, height: 90)
                        Image(systemName: "iphone.pattern.diagonalline")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 90, height: 90)
                    }
                    .padding(.top, 85)
                    
                    Text("Choose Your Background Style")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Text("You can change this later in the settings")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    VStack(spacing: 16) {
                        Picker("Background Type", selection: $backgroundType) {
                            Text("Map").tag(BackgroundType.map)
                            Text("Gradient").tag(BackgroundType.gradient)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        if backgroundType == .map {
                            Picker("Map Style", selection: $mapStyle) {
                                Text("Default").tag(MapStyle.standard)
                                Text("Satellite").tag(MapStyle.satellite)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .accentColor(.white)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(30)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    
                    if backgroundType == .gradient {
                        VStack(spacing: 16) {
                            ColorPicker("Start Color", selection: Binding(
                                get: { gradientStartColor },
                                set: { newValue in
                                    let uiColor = UIColor(newValue)
                                    var red: CGFloat = 0
                                    var green: CGFloat = 0
                                    var blue: CGFloat = 0
                                    var alpha: CGFloat = 0
                                    uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                                    gradientStartRed = Double(red)
                                    gradientStartGreen = Double(green)
                                    gradientStartBlue = Double(blue)
                                }
                            ))
                            .foregroundColor(.white)
                            ColorPicker("End Color", selection: Binding(
                                get: { gradientEndColor },
                                set: { newValue in
                                    let uiColor = UIColor(newValue)
                                    var red: CGFloat = 0
                                    var green: CGFloat = 0
                                    var blue: CGFloat = 0
                                    var alpha: CGFloat = 0
                                    uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                                    gradientEndRed = Double(red)
                                    gradientEndGreen = Double(green)
                                    gradientEndBlue = Double(blue)
                                }
                            ))
                            .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                    }
                    Spacer()
                }
                .offset(x: (showMapSettings && !mapSettingsHidden && showTrackingSettings) ? -UIScreen.main.bounds.width : (showMapSettings && !mapSettingsHidden ? 0 : UIScreen.main.bounds.width))
            }
            
            // Tracking Settings Section
            if showTrackingSettings {
                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 90, height: 90)
                        Image(systemName: "location.fill.viewfinder")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 90, height: 90)
                    }
                    .padding(.top, 85)
                    
                    Text("Track how many miles you listen to a Soundtrack")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Text("This is optional and can be changed in the settings.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    VStack(spacing: 16) {
                        Toggle("Track Distance Traveled", isOn: $locationTrackingEnabled)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(30)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                    HStack {
                        Text("Please read our ")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Button(action: {
                            showPrivacyPolicy = true
                        }) {
                            Text("Privacy Policy")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                                .underline()
                        }
                        Text(" for more info.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .sheet(isPresented: $showPrivacyPolicy) {
                        WebView(url: URL(string: "https://b-dog.co/pp")!)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    Spacer()
                }
                .offset(x: (showTrackingSettings && !aiModeHidden && showAIMode) ? -UIScreen.main.bounds.width : (showTrackingSettings && !aiModeHidden ? 0 : UIScreen.main.bounds.width))
            }
            
            // AI Mode Section
            if showAIMode && !aiModeHidden {
                VStack(spacing: 28) {
                    // Removed Spacer(minLength: 10) to bring content higher
                    ZStack {
                        Image("Gradient")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(aiGradientRotation))
                            .onAppear { aiGradientRotation = 0 }
                            .onReceive(aiGradientTimer) { _ in aiGradientRotation = (aiGradientRotation + 1).truncatingRemainder(dividingBy: 360) }
                        Button(action: { /* Placeholder, no-op */ }) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                                .frame(width: 90, height: 90)
                                .glassEffect()
                        }
                    }
                    .padding(.top, 40)
                    
                    // Updated font size and weight as requested
                    Text("Create a soundtrack effortlessly with AI")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Text("You get 1 soundtrack free. You'll need to supply your own files for manual soundtracks.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Text("$3/mo.")
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 22)
                        .background(
                          RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 100/255, green: 100/255, blue: 100/255))
                        )
                        .padding(.top, 40)
                        .padding(.horizontal, 30)
                    
                    Spacer()
                }
                .offset(x: showAIMode && !aiModeHidden && showSixthSection ? -UIScreen.main.bounds.width : (showAIMode && !aiModeHidden ? 0 : UIScreen.main.bounds.width))
            }
            
            // Sixth Section
            if showSixthSection && !sixthSectionHidden {
                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 90, height: 90)
                        Image(systemName: "car.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 90, height: 90)
                    }
                    .padding(.top, 85)
                        
                    Text("Let's get started.")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                       
                        
                    VStack(alignment: .leading, spacing: 10) {
                        InfoRow(number: "1", text: "Upload some audio files that will dynamically change based on your speed.")
                        InfoRow(number: "2", text: "Change when tracks fade in, and overall volume.")
                        InfoRow(number: "3", text: "Your soundtrack is ready to hit the road!")
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 10)

                    Text("I (the developer) am not responsible for what you do while driving. Be aware of posted speed limits and other signage.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    
                    .padding(.horizontal, 20)
                    .padding(.top, 40)

                    Spacer()
                }
                .offset(x: showSixthSection ? 0 : UIScreen.main.bounds.width)
            }
            
            // Button stays in place
            VStack {
                Spacer()
                if !(showingSecondPhase && !secondPhaseHidden) || (showMapSettings && !mapSettingsHidden) {
                    Button(action: {
                        if showMapSettings && !showTrackingSettings {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                showTrackingSettings = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                mapSettingsHidden = true
                                showMapSettings = false
                                secondPhaseHidden = true
                            }
                        } else if showTrackingSettings && !showAIMode {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                showAIMode = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                aiModeHidden = false
                                showTrackingSettings = false
                            }
                        } else if showAIMode && !showSixthSection {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                showSixthSection = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                aiModeHidden = true
                                showAIMode = false
                                sixthSectionHidden = false
                            }
                        } else {
                            aiModeHidden = false
                            mapSettingsHidden = false
                            secondPhaseHidden = false
                            withAnimation(.easeInOut(duration: 0.6)) {
                                showingSecondPhase = true
                                slideContent = true
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                locationViewModel.requestPermission()
                            }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

struct InfoRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 15) {
            Text(number)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
                .foregroundColor(.white)
            
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}

// (If this is a macOS project, change UIViewRepresentable to NSViewRepresentable and update accordingly)

#Preview {
    WelcomeScreen(isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
