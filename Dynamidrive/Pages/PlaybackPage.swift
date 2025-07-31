import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import MapKit
import ZIPFoundation

private struct DetentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PlaybackPage: View {
    @Binding var showPlaybackPage: Bool
    @Binding var pendingSoundtrack: Soundtrack?
    @Binding var showEditPage: Bool
    @Binding var showSpeedDetailPage: Bool
    @Binding var isRewindShowingCheckmark: Bool
    @EnvironmentObject private var audioController: AudioController
    @EnvironmentObject private var locationHandler: LocationHandler
    @State private var showShareSheet = false
    @State private var isCompactHeight = false
    @State private var currentHeight: CGFloat = .infinity
    @State private var isExporting = false
    
    @State private var minSpeedScale: [Int: CGFloat] = [:]
    @State private var maxSpeedScale: [Int: CGFloat] = [:]
    @State private var minSpeedBelow: [Int: Bool] = [:]
    @State private var maxSpeedBelow: [Int: Bool] = [:]
    @State private var scrollToBottom = false
    
    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
    }
    
    private func prepareForSharing() -> [Any] {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let soundtrack = pendingSoundtrack ?? Soundtrack(id: UUID(), title: audioController.currentSoundtrackTitle, tracks: audioController.currentTracks, players: audioController.currentPlayers, cardColor: .clear, isAI: false)
        
        // Create a temporary directory for sharing
        guard let tempBaseURL = try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: documentsDirectory,
            create: true
        ) else { return [] }
        
        let soundtrackFolder = tempBaseURL.appendingPathComponent(soundtrack.title)
        try? fileManager.createDirectory(at: soundtrackFolder, withIntermediateDirectories: true, attributes: nil)
        
        // Copy audio files and rename to display name
        var exportedFileNames: [String] = []
        for track in soundtrack.tracks {
            let sourceURL = documentsDirectory.appendingPathComponent(track.audioFileName)
            // Use display name as file name, sanitize for filesystem, and add .mp3 extension
            let sanitizedDisplayName = track.displayName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let exportFileName = sanitizedDisplayName + ".mp3"
            let destinationURL = soundtrackFolder.appendingPathComponent(exportFileName)
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
            exportedFileNames.append(exportFileName)
        }
        
        // Generate info.txt content referencing the new file names
        var infoText = "Dynamidrive Soundtrack: \(soundtrack.title)\n\n"
        for (index, track) in soundtrack.tracks.enumerated() {
            infoText += "Track: \(track.displayName)\n"
            infoText += "File: \(exportedFileNames[index])\n"
            if track.minimumSpeed == 0 && track.maximumSpeed == 0 {
                infoText += "Always playing\n"
            } else {
                infoText += "Speed range: \(track.minimumSpeed)-\(track.maximumSpeed) mph\n"
            }
            infoText += String(format: "Volume: %.1f\n\n", track.maximumVolume)
        }
        let infoURL = soundtrackFolder.appendingPathComponent("info.txt")
        try? infoText.write(to: infoURL, atomically: true, encoding: .utf8)
        
        // Zip the folder using ZIPFoundation
        let zipURL = tempBaseURL.appendingPathComponent("\(soundtrack.title).zip")
        do {
            try fileManager.zipItem(at: soundtrackFolder, to: zipURL)
        } catch {
            print("Failed to zip soundtrack folder: \(error)")
            return []
        }
        
        return [zipURL]
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content area
                Group {
                    if isCompactHeight {
                        // Compact view
                        HStack {
                            Spacer()
                            VStack {
                                if currentHeight > 100 && currentHeight <= 250 {
                                
                                    Text(pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle)
                                        .font(.system(size: 35, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .frame(maxWidth: UIScreen.main.bounds.width * 0.8)
                                        .multilineTextAlignment(.center)
                                        .padding(.top, 28)
                                    
                                    Spacer()
                                } else {
                                    Spacer()
                                }
                            }
                            Spacer()
                        }
                    } else {
                        ZStack {
                            let displayTracks = pendingSoundtrack?.tracks ?? audioController.currentTracks
                            
                            if displayTracks.count > 4 {
                                // Scrollable track list for more than 4 tracks
                                ScrollView {
                                    trackList()
                                        .padding(.horizontal)
                                        .padding(.top, -100) // Increased padding inside ScrollView to push content below header
                                        .padding(.bottom, 140)
                                        .allowsHitTesting(false)
                                }
                                .scrollIndicators(.hidden)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .ignoresSafeArea()
                            } else {
                                // Non-scrollable track list for 4 or fewer tracks
                                trackList()
                                    .padding(.horizontal)
                                    .padding(.top, 160)
                                    .padding(.bottom, 140)
                                    .allowsHitTesting(false)
                                    .frame(maxHeight: max(geometry.size.height - 200, 100)) // Add minimum height constraint
                                    .clipped()
                            }

                            VStack(spacing: 20) {
                                // Header
                                HStack {
                                    Text(pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle)
                                        .font(.system(size: 35, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                    Spacer()
                                    Button(action: {
                                        isExporting = true
                                        // Delay to allow UI update before heavy work
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            showShareSheet = true
                                        }
                                    }) {
                                        if isExporting {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .frame(width: 30, height: 30)
                                        } else {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white)
                                                .frame(width: 30, height: 30)
                                        }
                                    }
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .padding(.horizontal)
                                
                                // Speed Gauge
                                GeometryReader { geometry in
                                    speedGauge(geometry: geometry, displayedSpeed: Int(locationHandler.speedMPH.rounded()), animatedSpeed: .constant(locationHandler.speedMPH))
                                }
                                .frame(height: 50)
                                .padding(.horizontal)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                
                                Spacer()
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.top, 30)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.clear)
                
                // Playback buttons pinned to bottom
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        playbackButtons()
                        Spacer()
                    }
                    .padding(.bottom, 40) // Fixed padding instead of dynamic safe area insets
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
            .ignoresSafeArea()
            .sheet(isPresented: $showShareSheet, onDismiss: {
                isExporting = false
            }) {
                ShareSheet(activityItems: prepareForSharing())
            }
            .interactiveDismissDisabled(false)
            .zIndex(4)
            .preference(key: DetentHeightPreferenceKey.self, value: geometry.size.height)
            .onChange(of: geometry.size.height) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentHeight = newValue
                    isCompactHeight = newValue <= 220
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentHeight = geometry.size.height
                    isCompactHeight = geometry.size.height <= 220
                }
            }
        }
    }
    
    @ViewBuilder
    private func speedGauge(geometry: GeometryProxy, displayedSpeed: Int, animatedSpeed: Binding<Double>) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.5)) {
                showSpeedDetailPage = true
            }
        }) {
            HStack(spacing: 10) {
                Text("Speed")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 100, alignment: .leading)
                    .offset(x: -3)
                Spacer()
                if locationHandler.isSpeedUpdatesPaused {
                    Text("--")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text("\(displayedSpeed)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.default, value: displayedSpeed)
                }
                Gauge(value: animatedSpeed.wrappedValue, in: 0...180) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
                .tint(.white)
                .frame(width: geometry.size.width * 0.3)
                Text("mph")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .offset(y: -1)
            }
            .padding(.horizontal, 5)
        }
        .onAppear {
            animatedSpeed.wrappedValue = locationHandler.speedMPH
        }
    }
    
        @ViewBuilder
    private func trackList() -> some View {
        let displayTracks = pendingSoundtrack?.tracks ?? audioController.currentTracks
        let displayedTitle = pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle
        let isCurrentSoundtrack = audioController.currentSoundtrackTitle == displayedTitle && audioController.isSoundtrackPlaying
        
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 20) {
            ForEach(Array(displayTracks.enumerated()), id: \.offset) { index, track in
                trackCapsule(track: track, isCurrentSoundtrack: isCurrentSoundtrack)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .padding(.top, displayTracks.count > 4 ? 200 : -50) // Add extra padding when more than 4 tracks
    }
    
    @ViewBuilder
    private func trackCapsule(track: AudioController.SoundtrackData, isCurrentSoundtrack: Bool) -> some View {
        let displayedTitle = pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle
        let isPlaying = audioController.isSoundtrackPlaying && audioController.currentSoundtrackTitle == displayedTitle
        
        ZStack(alignment: .bottom) {
            // Background rounded rectangle
            RoundedRectangle(cornerRadius: 35)
                .fill(capsuleBackgroundColor(track: track, isCurrentSoundtrack: isCurrentSoundtrack))
                .frame(width: 120, height: 240)
                 .glassEffect(.regular.tint(.clear).interactive(),in: .rect(cornerRadius: 35.0))
                .overlay(
                    // Filling overlay from bottom up (only for speed-based tracks)
                    VStack(spacing: 0) {
                        Spacer()
                        capsuleFill(track: track, isCurrentSoundtrack: isCurrentSoundtrack)
                    }
                    .allowsHitTesting(false)
                )
                .clipShape(RoundedRectangle(cornerRadius: 35))
            
            // Track name inside rounded rectangle at bottom
            VStack {
                Spacer()
                Text(track.displayName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        .scaleEffect(isPlaying ? 1.0 : 0.9)
        .opacity(isPlaying ? 1.0 : 0.6)
        .animation(.spring(response: 1, dampingFraction: 0.5, blendDuration: 0), value: isPlaying)
    }
    
    private func capsuleBackgroundColor(track: AudioController.SoundtrackData, isCurrentSoundtrack: Bool) -> Color {
        let displayedTitle = pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle
        let isPlaying = audioController.isSoundtrackPlaying && audioController.currentSoundtrackTitle == displayedTitle
        
        if track.minimumSpeed == 0 && track.maximumSpeed == 0 {
            // Always playing tracks - change background based on playback state
            return isPlaying ? Color.white : Color.white.opacity(0.2)
        } else {
            // Speed-based tracks - semi-transparent background
            return Color.white.opacity(0.2)
        }
    }
    
    @ViewBuilder
    private func capsuleFill(track: AudioController.SoundtrackData, isCurrentSoundtrack: Bool) -> some View {
        // Only show fill for speed-based tracks
        if track.minimumSpeed != 0 || track.maximumSpeed != 0 {
            let currentSpeed = locationHandler.speedMPH
            let minSpeed = Double(track.minimumSpeed)
            let maxSpeed = Double(track.maximumSpeed)
            
            let fillPercentage: Double = {
                if currentSpeed < minSpeed {
                    return 0.0
                } else if currentSpeed > maxSpeed {
                    return 1.0
                } else {
                    return (currentSpeed - minSpeed) / (maxSpeed - minSpeed)
                }
            }()
            
            Rectangle()
                .fill(Color.white)
                .frame(width: 120, height: min(240 * fillPercentage, 240))
                .offset(y: fillPercentage >= 1.0 ? -3 : 0)
                .animation(.easeInOut(duration: 2.0), value: currentSpeed)
        }
    }
    
    @ViewBuilder
    private func playbackButtons() -> some View {
        VStack {
            Spacer()
            HStack(spacing: 80) {
                if audioController.isSoundtrackPlaying {
                    // AirPlay button when playing
                    Button(action: {
                        // Open AirPlay menu using MPVolumeView
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first {
                            let volumeView = MPVolumeView()
                            volumeView.showsRouteButton = true
                            volumeView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
                            window.addSubview(volumeView)
                            
                            // Find and trigger the route button
                            if let routeButton = volumeView.subviews.first(where: { $0 is UIButton }) as? UIButton {
                                routeButton.sendActions(for: .touchUpInside)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                volumeView.removeFromSuperview()
                            }
                        }
                    }) {
                        Image(systemName: "airplay.audio")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                } else {
                    // Rewind button when not playing
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        audioController.masterPlaybackTime = 0
                        for player in audioController.currentPlayers {
                            player?.currentTime = 0
                        }
                        audioController.updateNowPlayingInfo()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRewindShowingCheckmark = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isRewindShowingCheckmark = false
                            }
                        }
                    }) {
                        Image(systemName: isRewindShowingCheckmark ? "checkmark" : "backward.end.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                Button(action: {
                    if let pending = pendingSoundtrack, audioController.currentSoundtrackTitle != pending.title {
                        if audioController.isSoundtrackPlaying {
                            audioController.toggleSoundtrackPlayback()
                        }
                        audioController.setCurrentSoundtrack(id: pending.id, tracks: pending.tracks, players: pending.players, title: pending.title)
                        audioController.toggleSoundtrackPlayback()
                    } else {
                        audioController.toggleSoundtrackPlayback()
                    }
                }) {
                    let displayedTitle = pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle
                    let isCurrentAndPlaying = audioController.isSoundtrackPlaying && audioController.currentSoundtrackTitle == displayedTitle
                    Image(systemName: isCurrentAndPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                        .glassEffect(.regular.tint(.clear).interactive())
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showEditPage = true
                    }
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                        .glassEffect(.regular.tint(.clear).interactive())
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
           // .padding(.horizontal)
            .background(Color.clear)
        }
    }
}


