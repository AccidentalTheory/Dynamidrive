import SwiftUI
import MapKit

struct MasterSettings: View {
    @Binding var currentPage: AppPage
    @AppStorage("mapStyle") private var mapStyle: MapStyle = .standard
    @AppStorage("backgroundType") private var backgroundType: BackgroundType = .map
    @AppStorage("locationTrackingEnabled") private var locationTrackingEnabled: Bool = true
    @State private var showingDeleteConfirmation = false
    @EnvironmentObject private var locationHandler: LocationHandler
    
    // Gradient Start Color Components
    @AppStorage("gradientStartRed") private var gradientStartRed: Double = 0
    @AppStorage("gradientStartGreen") private var gradientStartGreen: Double = 122/255
    @AppStorage("gradientStartBlue") private var gradientStartBlue: Double = 1.0
    
    // Gradient End Color Components
    @AppStorage("gradientEndRed") private var gradientEndRed: Double = 88/255
    @AppStorage("gradientEndGreen") private var gradientEndGreen: Double = 86/255
    @AppStorage("gradientEndBlue") private var gradientEndBlue: Double = 214/255
    
    // Computed properties for gradient colors
    private var gradientStartColor: Color {
        get {
            Color(red: gradientStartRed, green: gradientStartGreen, blue: gradientStartBlue)
        }
        set {
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
    }
    
    private var gradientEndColor: Color {
        get {
            Color(red: gradientEndRed, green: gradientEndGreen, blue: gradientEndBlue)
        }
        set {
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
    }
    
    enum MapStyle: String {
        case standard
        case satellite
    }
    
    enum BackgroundType: String, Codable {
        case map
        case gradient
    }
    
    var body: some View {
        ZStack {
            // Main Content
            VStack(spacing: 40) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 35, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, UIScreen.main.bounds.height * 0.01)
                
                // Background Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("BACKGROUND")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        // Background Type Picker
                        Picker("Background Type", selection: $backgroundType) {
                            Text("Map").tag(BackgroundType.map)
                            Text("Gradient").tag(BackgroundType.gradient)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        if backgroundType == .map {
                            HStack {
                                Text("Map Style")
                                    .foregroundColor(.white)
                                Spacer()
                                Picker("Map Style", selection: $mapStyle) {
                                    Text("Default").tag(MapStyle.standard)
                                    Text("Satellite").tag(MapStyle.satellite)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .accentColor(.white)
                            }
                            .padding(.horizontal)
                        } else {
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
                    }
                    .padding(.vertical)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(30)
                }
                .padding(.horizontal)
                
                // Location Privacy Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("LOCATION PRIVACY")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        Toggle("Track Distance Traveled", isOn: $locationTrackingEnabled)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Text("Delete All Distance Data")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.12))
                                )
                                .glassEffect(.regular.tint(.red).interactive())
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(30)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Are you sure?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    locationHandler.resetAllDistanceData()
                }
            } message: {
                Text("This will completely reset all of your distance traveled data. It cannot be undone.")
            }
            
            // Empty stack between content and buttons
            ZStack {
            }
            .frame(height: 150)
            .allowsHitTesting(false)
            
            // Fixed bottom controls
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentPage = .main
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    
                    // Invisible button for layout balance
                    Button(action: {}) {
                        Color.clear
                            .frame(width: 50, height: 50)
                    }
                    .opacity(0)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
    }
} 
