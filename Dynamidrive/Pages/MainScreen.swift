import SwiftUI
import AVFoundation
import UIKit

extension Font {
    static func ppNeueMachina(size: CGFloat) -> Font {
        return .custom("PPNeueMachina-Ultrabold", size: size)
    }
}

struct MainScreen: View {
    @Binding var currentPage: AppPage
    @Binding var showCreatePage: Bool
    @Binding var showImportPage: Bool
    @Binding var importedSoundtrackURL: URL?
    @Binding var showPlaybackPage: Bool
    @Binding var pendingSoundtrack: Soundtrack?
    @Binding var soundtracks: [Soundtrack]
    @Binding var animateCards: Bool
    @Binding var hasAnimatedOnce: Bool
    @Binding var isMainScreenEditMode: Bool
    @Binding var soundtracksBeingDeleted: Set<UUID>
    @EnvironmentObject private var audioController: AudioController
    @EnvironmentObject private var locationHandler: LocationHandler
    @Binding var previousPage: AppPage?
    @AppStorage("locationTrackingEnabled") private var locationTrackingEnabled: Bool = true
    @AppStorage("hasSeenWelcomeScreen") private var hasSeenWelcomeScreen = false
    @AppStorage("hasGrantedLocationPermission") private var hasGrantedLocationPermission = false
    @AppStorage("sortOption") private var sortOptionRaw: String = "Creation Date"
    @AppStorage("isSortChevronUp") private var isSortChevronUp: Bool = false
    
    @State private var showWelcomeScreen = false
    @State private var showLocationDeniedView = false
    
    // Add state to track if content is scrolled
    @State private var isScrolled = false
    
    var cardAnimationDelay: Double = 0
    
    var resetCreatePage: () -> Void
    var deleteSoundtrack: (Soundtrack) -> Void

    // Helper to get the selected sort option
    private var sortOption: SortOption {
        SortOption(rawValue: sortOptionRaw) ?? .creationDate
    }

    // Sorted soundtracks based on the selected sort option
    private var sortedSoundtracks: [Soundtrack] {
        switch sortOption {
        case .creationDate:
            // Assuming the array is already in creation order (oldest first)
            let arr = soundtracks
            return isSortChevronUp ? arr.reversed() : arr
        case .name:
            let arr = soundtracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return isSortChevronUp ? arr.reversed() : arr
        case .distancePlayed:
            let arr = soundtracks.sorted {
                let d0 = locationHandler.soundtrackDistances[$0.id] ?? 0.0
                let d1 = locationHandler.soundtrackDistances[$1.id] ?? 0.0
                return d0 > d1
            }
            return isSortChevronUp ? arr.reversed() : arr
        case .amountOfTracks:
            let arr = soundtracks.sorted { $0.tracks.count > $1.tracks.count }
            return isSortChevronUp ? arr.reversed() : arr
        }
    }

    // SortOption enum (should match MasterSettings)
    enum SortOption: String, CaseIterable, Identifiable {
        case creationDate = "Creation Date"
        case name = "Name"
        case distancePlayed = "Distance Played"
        case amountOfTracks = "Amount of tracks"
        var id: String { self.rawValue }
    }
    
    var body: some View {
        ZStack {
            Group {
                VStack(spacing: 40) {
                    if soundtracks.isEmpty {
                        Spacer()
                        if hasGrantedLocationPermission {
                            VStack(spacing: 0) {
                                Image(systemName: "plus")
                                    .font(.system(size: 160))
                                    .foregroundColor(.white)
                                    .opacity(0.4)
                                    .frame(width: 180, height: 180)
                                Text("Press the new button to make your first soundtrack")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.white)
                                    .opacity(0.4)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 20) {
                                Button(action: {
                                    showLocationDeniedView = true
                                }) {
                                    Image(systemName: "location.slash.fill")
                                        .font(.system(size: 160))
                                        .foregroundColor(.white)
                                        .opacity(0.4)
                                        .frame(width: 180, height: 180)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                            .padding(.top, 80)
                        }
                        Spacer()
                        Spacer()
                    } else {
                        // ScrollView with scroll detection
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                GeometryReader { geo in
                                    Color.clear
                                        .frame(height: 0)
                                        .onChange(of: geo.frame(in: .named("scroll")).minY) { value in
                                            // If scrolled down, set isScrolled to true
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                isScrolled = value < -8 // adjust threshold as needed
                                            }
                                        }
                                }
                                .frame(height: 0)
                                VStack(spacing: 14) {
                                    Color.clear.frame(height: UIScreen.main.bounds.height * 0.08)
                                    ForEach(sortedSoundtracks.indices, id: \ .self) { index in
                                        let soundtrack = sortedSoundtracks[index]
                                        let delay = cardAnimationDelay + Double(index) * 0.1
                                        InViewScrollEffect(triggerArea: 1, blur: 10, scale: 0.66) {
                                            soundtrackCard(soundtrack: soundtrack, index: index, delay: delay)
                                        }
                                        .frame(height: 108)
                                        .padding(.horizontal)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.3), value: soundtracks)
                                .padding(.bottom, 100)
                            }
                            .coordinateSpace(name: "scroll")
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Gradient behind header
            VStack {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.black.opacity(0.6), location: 0.0),
                        .init(color: Color.black.opacity(0.6), location: 0.35),
                        .init(color: Color.clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .opacity(isScrolled ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isScrolled)
                Spacer()
            }
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .top)

            VStack {
                HStack {
                    if animateCards {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                currentPage = .masterSettings
                            }
                        }) {
                            Image(systemName: "gear")
                                .globalButtonStyle()
                        }
                        .glassEffectTransition(.materialize)
                    }
                    Spacer()
                    if animateCards {
                        Text("Dynamidrive")
                            .font(.ppNeueMachina(size: 25))
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
                            .glassEffectTransition(.materialize)
                    }
                    Spacer()
                    if animateCards {
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            isMainScreenEditMode.toggle()
                        }) {
                            Image(systemName: isMainScreenEditMode ? "checkmark" : "minus.circle")
                                .globalButtonStyle()
                        }
                        .disabled(!hasGrantedLocationPermission)
                        .simultaneousGesture(TapGesture().onEnded {
                            if !hasGrantedLocationPermission {
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.error)
                            }
                        })
                        .glassEffectTransition(.materialize)
                    }
                }
                .padding(.horizontal)
                .padding(.top, UIScreen.main.bounds.height * 0.01)
                Spacer()
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if animateCards {
                        Menu {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    showImportPage = true
                                    showCreatePage = false
                                    currentPage = .create
                                }
                            }) {
                                Label("Import Existing (Coming Soon)", systemImage: "square.and.arrow.down")
                                    .foregroundColor(.gray)
                            }
                            .disabled(true)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    resetCreatePage()
                                    showCreatePage = true
                                    showImportPage = false
                                    importedSoundtrackURL = nil
                                    currentPage = .create
                                }
                            }) {
                                Label("Create New...", systemImage: "plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .globalButtonStyle()
                        }
                        .disabled(!hasGrantedLocationPermission)
                        .glassEffectTransition(.materialize)
                    }
                    Spacer()
                }
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showWelcomeScreen) {
            WelcomeScreen(isPresented: $showWelcomeScreen)
        }
        .sheet(isPresented: $showLocationDeniedView) {
            LocationDeniedView()
        }
        .interactiveDismissDisabled()
        .onChange(of: animateCards) { newValue in
            if newValue {
                if !hasSeenWelcomeScreen {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        showWelcomeScreen = true
                    }
                } else if !hasGrantedLocationPermission {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        showLocationDeniedView = true
                    }
                }
            }
        }
    }
    
    private func soundtrackCard(soundtrack: Soundtrack, index: Int, delay: Double) -> some View {
        ZStack {
            GlobalCardAppearance
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: {
                        pendingSoundtrack = soundtrack
                        previousPage = currentPage
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showPlaybackPage = true
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(soundtrack.title)
                                .foregroundColor(.white)
                                .font(.system(size: 28, weight: .semibold))
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                .minimumScaleFactor(0.3)
                                .multilineTextAlignment(.leading)
                                .lineLimit(1)
                            
                            if locationTrackingEnabled {
                                let miles = locationHandler.soundtrackDistances[soundtrack.id] ?? 0.0
                                Text("Distance Played: \(Int(miles)) mi")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .id(locationHandler.soundtrackDistances[soundtrack.id] ?? 0.0)
                
                if !isMainScreenEditMode {
                    let isCurrentAndPlaying = audioController.isSoundtrackPlaying && audioController.currentSoundtrackTitle == soundtrack.title
                    Button(action: {
                        if audioController.currentSoundtrackTitle != soundtrack.title {
                            if audioController.isSoundtrackPlaying {
                                audioController.toggleSoundtrackPlayback()
                            }
                            audioController.setCurrentSoundtrack(id: soundtrack.id, tracks: soundtrack.tracks, players: soundtrack.players, title: soundtrack.title)
                            audioController.toggleSoundtrackPlayback()
                        } else {
                            audioController.toggleSoundtrackPlayback()
                        }
                    }) {
                        Image(systemName: isCurrentAndPlaying ? "pause.fill" : "play.fill")
                            .CardButtonStyle()
                    }
                } else {
                    Button(action: {
                       
                        soundtracksBeingDeleted.insert(soundtrack.id)
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            deleteSoundtrack(soundtrack)
                            soundtracksBeingDeleted.remove(soundtrack.id)
                        }
                    }) {
                        Image(systemName: "minus")
                            .MinusButtonStyle()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 108)
        .opacity(soundtracksBeingDeleted.contains(soundtrack.id) ? 0 : 1)
        .scaleEffect(soundtracksBeingDeleted.contains(soundtrack.id) ? 0.8 : 1)
        .animation(.easeInOut(duration: 0.3), value: soundtracksBeingDeleted)
        .modifier(FlyInCardEffect(isVisible: animateCards, delay: delay))
    }
}

private struct FlyInCardEffect: ViewModifier {
    let isVisible: Bool
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 60)
            .blur(radius: isVisible ? 0 : 24)
            .animation(
                isVisible ? .interpolatingSpring(stiffness: 80, damping: 10).delay(delay) : .none,
                value: isVisible
            )
            .allowsHitTesting(isVisible)
    }
}

private struct InViewScrollEffect<Content: View>: View {
    let triggerArea: CGFloat
    let blur: CGFloat
    let scale: CGFloat
    let content: () -> Content
    @State private var visibleFraction: CGFloat = 1.0

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let screen = UIScreen.main.bounds
            
            let visible = max(0, min(frame.maxY, screen.maxY) - max(frame.minY, screen.minY))
            let fraction = min(max(visible / frame.height, 0), 1)
            let trigger = (fraction > triggerArea) ? 1.0 : (fraction / triggerArea)

            content()
                .blur(radius: (1.0 - trigger) * blur)
                .scaleEffect(1.0 - (1.0 - trigger) * (1.0 - scale))
                .animation(.easeInOut(duration: 0.3), value: trigger)
                .onAppear {
                    visibleFraction = trigger
                }
                .onChange(of: fraction) { newValue in
                    visibleFraction = trigger
                }
        }
    }
}
