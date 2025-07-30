import SwiftUI
import MapKit
import UIKit

// Move SortOption enum outside the struct to make it globally accessible
public enum SortOption: String, CaseIterable, Identifiable {
    case creationDate = "Creation Date"
    case name = "Name"
    case distancePlayed = "Distance Played"
    case amountOfTracks = "Amount of tracks"
    case color = "Color" // Added for color sorting
    
    public var id: String { self.rawValue }
    
    static var orderedCases: [SortOption] {
        [.creationDate, .name, .distancePlayed, .amountOfTracks, .color] // Added color
    }
}

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
    
    @AppStorage("showMutedLocationIndicator") private var showMutedLocationIndicator: Bool = false
    @AppStorage("forceClearCardColor") private var forceClearCardColor: Bool = false // New toggle for clear card color
    @AppStorage("sortOption") private var sortOption: SortOption = .distancePlayed
    @AppStorage("isSortChevronUp") private var isSortChevronUp: Bool = false
    @State private var showSortOrderText: Bool = false
    
    enum MapStyle: String {
        case standard
        case satellite
        case muted // New case for Muted map style
    }
    
    enum BackgroundType: String, Codable {
        case map
        case gradient
    }
    
    var body: some View {
        PageLayout(
            title: "Settings",
            leftButtonAction: {
                if let url = URL(string: "https://Dynamidrive.App") {
                    UIApplication.shared.open(url)
                }
            },
            rightButtonAction: {
                if let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLScfTst50SemFPtMZBWX17CqOQPK5pGM8SwJ3m3LbIlYcnWLpg/viewform?usp=dialog") {
                    UIApplication.shared.open(url)
                }
            },
            leftButtonSymbol: "globe",
            rightButtonSymbol: "exclamationmark.bubble",
            bottomButtons: [
                PageButton(
                    label: {
                        Image(systemName: "arrow.uturn.backward")
                            .globalButtonStyle()
                    },
                    action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentPage = .main
                        }
                    }
                )
            ]
        ) {
            VStack(spacing: 40) {
                // SORT BY Section (now as vertical card-styled buttons)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SORT BY")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Spacer()
                        if showSortOrderText {
                            Text(isSortChevronUp ? "Ascending" : "Descending")
                                .foregroundColor(.gray)
                                .transition(GlobalPageTransition)
                                .animation(.easeInOut(duration: 0.3), value: showSortOrderText)
                        }
                        Button(action: {
                            isSortChevronUp.toggle()
                            showSortOrderText = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    showSortOrderText = false
                                }
                            }
                        }) {
                            Image(systemName: isSortChevronUp ? "chevron.up" : "chevron.down")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    VStack(spacing: 0) {
                        ForEach(SortOption.orderedCases) { option in
                            Button(action: {
                                sortOption = option
                            }) {
                                HStack {
                                    Text(option.rawValue)
                                        .foregroundColor(.white)
                                        .fontWeight(sortOption == option ? .bold : .regular)
                                    Spacer()
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .fontWeight(.bold)
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    .background(GlobalCardAppearance)
                    
                }
                .padding(.horizontal)
                
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
                        .onChange(of: backgroundType) { newBackgroundType in
                            // If user switches to gradient, turn off forceClearCardColor
                            if newBackgroundType == .gradient {
                                forceClearCardColor = false
                            } else if newBackgroundType == .map && mapStyle == .muted {
                                // If user switches back to map and it's set to muted, turn on forceClearCardColor
                                forceClearCardColor = true
                            }
                        }
                        
                        if backgroundType == .map {
                            HStack {
                                Text("Map Style")
                                    .foregroundColor(.white)
                                Spacer()
                                Picker("Map Style", selection: $mapStyle) {
                                    Text("Default").tag(MapStyle.standard)
                                    Text("Satellite").tag(MapStyle.satellite)
                                    Text("Monotone").tag(MapStyle.muted)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .accentColor(.white)
                            }
                            .padding(.horizontal)
                            .onChange(of: mapStyle) { newMapStyle in
                                // If user selects a map style other than muted, turn off forceClearCardColor
                                if newMapStyle != .muted {
                                    forceClearCardColor = false
                                } else {
                                    // If user switches back to muted map, turn on forceClearCardColor
                                    forceClearCardColor = true
                                }
                            }
                            // Show toggle only if Muted is selected
                            if mapStyle == .muted {
                                Toggle("Show Location Indicator", isOn: $showMutedLocationIndicator)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                Toggle("Force Clear Card Color", isOn: $forceClearCardColor)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                            }
                        } else {
                            VStack(spacing: 16) {
                                ColorPicker("Top Color", selection: Binding(
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
                                ColorPicker("Bottom Color", selection: Binding(
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
                    .background(
                        GlobalCardAppearance
                    )
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
                    .background(
                        GlobalCardAppearance
                            
                    )
                }
                .padding(.horizontal)
            }
        }
        .alert("Are you sure?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                locationHandler.resetAllDistanceData()
            }
        } message: {
            Text("This will completely reset all of your distance traveled data. It cannot be undone.")
        }
    }
} 

