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
    @AppStorage("forceClearCardColor") private var forceClearCardColor: Bool = false // Read the toggle
    
    @State private var showWelcomeScreen = false
    @State private var showLocationDeniedView = false
    @State private var showPlusMenu = false
    
    // Add state to track if content is scrolled
    @State private var isScrolled = false
    
    @Namespace private var cardNamespace
    @State private var previousOrder: [UUID] = []
    @State private var isAnimatingReorder: Bool = false
    @State private var cardPositions: [UUID: Int] = [:]
    @State private var animationProgress: Double = 0.0
    
    var cardAnimationDelay: Double = 0
    
    var resetCreatePage: () -> Void
    var deleteSoundtrack: (Soundtrack) -> Void

    // Helper to get the selected sort option
    private var sortOption: SortOption {
        SortOption(rawValue: sortOptionRaw) ?? .creationDate
    }

    // Helper to map a Color to a rainbow order index
    private func rainbowOrderIndex(for color: Color) -> Int {
        // Define a fixed rainbow order: Red, Orange, Yellow, Green, Blue, Indigo, Violet, Clear, Other
        // You may need to adjust the RGB values to match your app's color palette
        let rainbow: [(name: String, color: Color)] = [
            ("Red", Color.red),
            ("Orange", Color.orange),
            ("Yellow", Color.yellow),
            ("Green", Color.green),
            ("Blue", Color.blue),
            ("Indigo", Color(red: 75/255, green: 0, blue: 130/255)),
            ("Violet", Color.purple),
            ("Clear", Color.clear)
        ]
        // Find the closest color in the rainbow array
        func colorDistance(_ c1: Color, _ c2: Color) -> Double {
            let ui1 = UIColor(c1)
            let ui2 = UIColor(c2)
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            ui1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            ui2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return pow(Double(r1 - r2), 2) + pow(Double(g1 - g2), 2) + pow(Double(b1 - b2), 2)
        }
        var minIndex = rainbow.count // Default to "Other"
        var minDistance = Double.greatestFiniteMagnitude
        for (i, entry) in rainbow.enumerated() {
            let dist = colorDistance(color, entry.color)
            if dist < minDistance {
                minDistance = dist
                minIndex = i
            }
        }
        return minIndex
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
        case .color:
            let arr = soundtracks.sorted {
                rainbowOrderIndex(for: $0.cardColor) < rainbowOrderIndex(for: $1.cardColor)
            }
            return isSortChevronUp ? arr.reversed() : arr
        }
    }
    
    // Use SortOption from MasterSettings.swift
    
    var body: some View {
        PageLayout(
            title: "Dynamidrive",
            leftButtonAction: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentPage = .masterSettings
                }
            },
            rightButtonAction: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                isMainScreenEditMode.toggle()
            },
            leftButtonSymbol: "gear",
            rightButtonSymbol: isMainScreenEditMode ? "checkmark" : "minus.circle",
            bottomButtons: [
                PageButton(label: {
                    Image(systemName: "plus").globalButtonStyle()
                }, action: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        resetCreatePage()
                        showCreatePage = true
                        showImportPage = false
                        importedSoundtrackURL = nil
                        currentPage = .create
                    }
                })
            ],
            verticalPadding: 0,
            useCustomFont: true
        ) {
            ZStack(alignment: .center) {
                VStack(spacing: 40) {
                    if !soundtracks.isEmpty {
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(spacing: 10) {
                                    Color.clear.frame(height: UIScreen.main.bounds.height * 0.08)
                                    ForEach(sortedSoundtracks.indices, id: \.self) { index in
                                        let soundtrack = sortedSoundtracks[index]
                                        let delay = cardAnimationDelay + Double(index) * 0.1
                                        InViewScrollEffect(triggerArea: 1, blur: 10, scale: 0.66) {
                                            soundtrackCard(soundtrack: soundtrack, index: index, delay: delay)
                                        }
                                        .frame(height: 108)
                                        .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.3), value: soundtracks)
                                .padding(.bottom, 100)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if soundtracks.isEmpty {
                    VStack {
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
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .padding(.horizontal)
                    .offset(y: 180)
                }
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
        .onAppear {
            if !hasGrantedLocationPermission {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showLocationDeniedView = true
                }
            }
            // Initialize card positions
            let newOrder = sortedSoundtracks.map { $0.id }
            for (index, id) in newOrder.enumerated() {
                cardPositions[id] = index
            }
            previousOrder = newOrder
        }
        .onChange(of: sortedSoundtracks.map { $0.id }) { newOrder in
            let oldOrder = previousOrder
            
            // Only animate if the order actually changed
            if oldOrder != newOrder {
                // Start reorder animation
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAnimatingReorder = true
                    animationProgress = 0.0
                }
                
                // Update card positions
                for (index, id) in newOrder.enumerated() {
                    cardPositions[id] = index
                }
                
                // Animate both scaling and movement with spring animation
                withAnimation(.spring(response: 0.8, dampingFraction: 0.6, blendDuration: 0.1)) {
                    animationProgress = 1.0
                }
                
                // Reset animation state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAnimatingReorder = false
                        animationProgress = 0.0
                    }
                }
            }
            
            previousOrder = newOrder
        }
        .onChange(of: hasGrantedLocationPermission) { newValue in
            if !newValue {
                showLocationDeniedView = true
            }
        }
        
        .onChange(of: currentPage) { newPage in
            // Exit edit mode when switching pages with a 1-second delay
            if isMainScreenEditMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isMainScreenEditMode = false
                    }
                }
            }
        }
 
        .onReceive(locationHandler.$soundtrackDistances) { _ in
          
        }
    }
    
    private func soundtrackCard(soundtrack: Soundtrack, index: Int, delay: Double) -> some View {
        let cardColor = forceClearCardColor ? Color.clear : soundtrack.cardColor
        let oldPosition = previousOrder.firstIndex(of: soundtrack.id) ?? index
        let newPosition = index
        let isMovingUp = oldPosition > newPosition
        let isMovingDown = oldPosition < newPosition
        
        // Calculate animation values based on movement direction
        let scaleEffect: Double = {
            if isAnimatingReorder {
                if isMovingUp {
                    // Bottom card moving up: scale up to peak, then gradually reduce
                    let scalePeak = 0.15
                    let scaleProgress = animationProgress
                    if scaleProgress <= 0.3 {
                        // Rapid scaling up in first 30%
                        return 1.0 + (scalePeak * (scaleProgress / 0.3))
                    } else if scaleProgress <= 0.5 {
                        // Hold peak scale for a moment
                        return 1.0 + scalePeak
                    } else {
                        // Gradually reduce scale as it moves
                        let remainingProgress = (scaleProgress - 0.5) / 0.5
                        return 1.0 + (scalePeak * (1.0 - remainingProgress))
                    }
                } else if isMovingDown {
                    // Top card moving down: scale down to peak, then gradually reduce
                    let scalePeak = 0.1
                    let scaleProgress = animationProgress
                    if scaleProgress <= 0.3 {
                        // Rapid scaling down in first 30%
                        return 1.0 - (scalePeak * (scaleProgress / 0.3))
                    } else if scaleProgress <= 0.5 {
                        // Hold peak scale for a moment
                        return 1.0 - scalePeak
                    } else {
                        // Gradually reduce scale as it moves
                        let remainingProgress = (scaleProgress - 0.5) / 0.5
                        return 1.0 - (scalePeak * (1.0 - remainingProgress))
                    }
                }
            }
            return 1.0
        }()
        
        let blurEffect: Double = {
            if isAnimatingReorder && isMovingDown {
                return 8.0 * animationProgress
            }
            return 0.0
        }()
        
        let offsetEffect: Double = {
            if isAnimatingReorder {
                let cardHeight: Double = 108.0
                let spacing: Double = 20.0
                let totalCardHeight = cardHeight + spacing
                
                // Only start moving after scaling is complete and held (after 50% of animation)
                let movementProgress = max(0, (animationProgress - 0.5) / 0.5)
                
                if isMovingUp {
                    return -totalCardHeight * movementProgress
                } else if isMovingDown {
                    return totalCardHeight * movementProgress
                }
            }
            return 0.0
        }()
        
        // Calculate z-index to ensure bottom card appears on top during animation
        let zIndex: Double = {
            if isAnimatingReorder {
                if isMovingUp {
                    // Bottom card moving up should be on top throughout animation
                    return 100.0
                } else if isMovingDown {
                    // Top card moving down should be behind throughout animation
                    return -100.0
                }
            }
            return 0.0
        }()
        
        return ZStack {
            Rectangle()
                .fill(.clear)
                .cornerRadius(20)
                .glassEffect(.regular.tint(cardColor == .clear ? .clear : cardColor).interactive(), in: .rect(cornerRadius: 20.0))
            
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
                            HStack(alignment: .center, spacing: 4) {
                                Text(soundtrack.title)
                                    .foregroundColor(.white)
                                    .font(.system(size: 28, weight: .semibold))
                                    .minimumScaleFactor(0.3)
                                    .lineLimit(1)
                                
                                if soundtrack.isAI {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .medium))
                                }
                            }
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            
                            if locationTrackingEnabled {
                                let miles = locationHandler.soundtrackDistances[soundtrack.id] ?? 0.0
                                Text("Distance Played: \(Int(miles)) mi")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .medium))
                                    .contentTransition(.numericText())
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
                                        // --- AI REBUILD LOGIC START ---
            if soundtrack.isAI {
                // Attempt to rebuild players from disk
                let fileManager = FileManager.default
                guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                let aiDownloadedFilesPath = documentsDirectory.appendingPathComponent("AI_Downloaded_Files")
                var rebuiltPlayers: [AVAudioPlayer?] = []
                var failedTracks: [String] = []
                
                // Debug: List all files in AI_Downloaded_Files directory
                do {
                    let contents = try fileManager.contentsOfDirectory(at: aiDownloadedFilesPath, includingPropertiesForKeys: nil)
                    print("[MainScreen] Found \(contents.count) files in AI_Downloaded_Files:")
                    for file in contents {
                        print("[MainScreen] - \(file.lastPathComponent)")
                    }
                } catch {
                    print("[MainScreen] Error listing AI_Downloaded_Files: \(error)")
                }
                
                for track in soundtrack.tracks {
                    print("[MainScreen] Looking for track: \(track.displayName) with filename: \(track.audioFileName)")
                    var audioURL: URL?
                    
                    // For AI soundtracks, files should be in main documents directory after creation
                    // First, try the main documents directory
                    let mainFileURL = documentsDirectory.appendingPathComponent(track.audioFileName)
                    if fileManager.fileExists(atPath: mainFileURL.path) {
                        audioURL = mainFileURL
                        print("[MainScreen] Found in main documents directory: \(mainFileURL.path)")
                    } else {
                        // Fallback: try AI_Downloaded_Files directory (in case files weren't cleaned up)
                        let exactFileURL = aiDownloadedFilesPath.appendingPathComponent(track.audioFileName)
                        if fileManager.fileExists(atPath: exactFileURL.path) {
                            audioURL = exactFileURL
                            print("[MainScreen] Found in AI_Downloaded_Files: \(exactFileURL.path)")
                        } else {
                            // If exact match not found, try different extensions in AI_Downloaded_Files
                            let baseName = track.audioFileName.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "").replacingOccurrences(of: ".wav", with: "")
                            let possibleExtensions = [".m4a", ".mp3", ".wav"]
                            
                            for ext in possibleExtensions {
                                let testFileName = baseName + ext
                                let testURL = aiDownloadedFilesPath.appendingPathComponent(testFileName)
                                if fileManager.fileExists(atPath: testURL.path) {
                                    audioURL = testURL
                                    print("[MainScreen] Found extension match in AI_Downloaded_Files: \(testURL.path)")
                                    break
                                }
                            }
                        }
                    }
                    
                    guard let finalAudioURL = audioURL else {
                        print("[MainScreen] No valid audio URL found for \(track.audioFileName)")
                        failedTracks.append(track.displayName)
                        rebuiltPlayers.append(nil)
                        continue
                    }
                    
                    do {
                        let player = try AVAudioPlayer(contentsOf: finalAudioURL)
                        player.volume = mapVolume(track.maximumVolume)
                        player.prepareToPlay()
                        print("[MainScreen] Successfully created player for \(track.displayName) with duration: \(player.duration) seconds")
                        rebuiltPlayers.append(player)
                    } catch {
                        print("[MainScreen] Failed to create player for \(track.displayName): \(error)")
                        failedTracks.append(track.displayName)
                        rebuiltPlayers.append(nil)
                    }
                }
                
                if failedTracks.isEmpty {
                    print("[MainScreen] All AI tracks loaded successfully, starting playback")
                    audioController.setCurrentSoundtrack(id: soundtrack.id, tracks: soundtrack.tracks, players: rebuiltPlayers, title: soundtrack.title)
                    audioController.toggleSoundtrackPlayback()
                } else {
                    print("[MainScreen] Failed to load tracks: \(failedTracks)")
                    // Show alert for failed tracks
                    let alert = UIAlertController(title: "Playback Error", message: "Could not load the following tracks for playback:\n\n" + failedTracks.joined(separator: ", "), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(alert, animated: true)
                    }
                }
            } else {
                audioController.setCurrentSoundtrack(id: soundtrack.id, tracks: soundtrack.tracks, players: soundtrack.players, title: soundtrack.title)
                audioController.toggleSoundtrackPlayback()
            }
            // --- AI REBUILD LOGIC END ---
                        } else {
                            audioController.toggleSoundtrackPlayback()
                        }
                    }) {
                        if cardColor == .clear {
                            Image(systemName: isCurrentAndPlaying ? "pause.fill" : "play.fill")
                                .globalButtonStyle()
                        } else {
                            Image(systemName: isCurrentAndPlaying ? "pause.fill" : "play.fill")
                                .CardButtonStyle()
                        }
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
                        if cardColor == .clear {
                            Image(systemName: "minus")
                                .globalButtonStyle()
                        } else {
                            Image(systemName: "minus")
                                .MinusButtonStyle()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 108)
        .opacity(soundtracksBeingDeleted.contains(soundtrack.id) ? 0 : 1)
        .scaleEffect(soundtracksBeingDeleted.contains(soundtrack.id) ? 0.8 : scaleEffect)
        .offset(y: offsetEffect)
        .blur(radius: blurEffect)
        .zIndex(zIndex)
        .animation(.easeInOut(duration: 0.3), value: soundtracksBeingDeleted)
        .modifier(FlyInCardEffect(isVisible: animateCards, delay: delay))
        .matchedGeometryEffect(id: soundtrack.id, in: cardNamespace)
    }
    
    // Helper function to map volume percentage to AVAudioPlayer volume
    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
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
