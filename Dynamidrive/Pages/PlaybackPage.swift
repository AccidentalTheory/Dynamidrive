import SwiftUI
import AVFoundation
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
    @State private var isClockActive = false
    
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
        
        let soundtrack = pendingSoundtrack ?? Soundtrack(id: UUID(), title: audioController.currentSoundtrackTitle, tracks: audioController.currentTracks, players: audioController.currentPlayers, cardColor: .clear)
        
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
                                
                                playbackButtons()
                                Spacer()
                            } else {
                                
                                Spacer()
                                playbackButtons()
                                Spacer()
                            }
                        }
                        Spacer()
                    }
                } else {
                    ZStack {
                        ScrollViewReader { proxy in
                            let displayTracks = pendingSoundtrack?.tracks ?? audioController.currentTracks
                            let shouldDisableScroll = displayTracks.count <= 4
                            
                            ScrollView(.vertical, showsIndicators: false) {
                                trackList()
                                    .padding(.horizontal)
                                    .padding(.top, 160)
                                    .padding(.bottom, 140)
                                    .id("trackListBottom")
                            }
                            .disabled(shouldDisableScroll)
                            .ignoresSafeArea()
                            .onAppear {
                                if shouldDisableScroll {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("trackListBottom", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                            .onChange(of: pendingSoundtrack) { oldValue, newValue in
                                let newDisplayTracks = newValue?.tracks ?? audioController.currentTracks
                                let newShouldDisableScroll = newDisplayTracks.count <= 4
                                if newShouldDisableScroll {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("trackListBottom", anchor: .bottom)
                                        }
                                    }
                                }
                            }
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
                            }
                            .padding(.horizontal)
                            
                            // Speed Gauge
                            GeometryReader { geometry in
                                speedGauge(geometry: geometry, displayedSpeed: Int(locationHandler.speedMPH.rounded()), animatedSpeed: .constant(locationHandler.speedMPH))
                            }
                            .frame(height: 50)
                            .padding(.horizontal)
                            
                            Spacer()
                        }

                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                playbackButtons()
                                Spacer()
                            }
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                        }
                        .ignoresSafeArea()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.top, 30)
                }
            }
            .background(.clear)
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
        VStack(spacing: 20) {
            if !displayTracks.isEmpty && displayTracks[0].audioFileName.contains("Base") {
                GeometryReader { geometry in
                    ZStack {
                        GlobalCardAppearance
                        HStack(alignment: .center, spacing: 0) {
                            Text(displayTracks[0].displayName)
                                .font(.system(size: 35, weight: .semibold))
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                .minimumScaleFactor(0.3)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .foregroundColor(.white)
                                .padding(.leading, 16)
                            Spacer()
                            AudioBarsView(isPlaying: audioController.isSoundtrackPlaying, currentSoundtrackTitle: displayedTitle)
                                .frame(width: 70, height: 50)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .frame(height: 108)
            }
            if displayTracks.count > 1 {
                ForEach(1..<displayTracks.count, id: \.self) { index in
                    GeometryReader { geometry in
                        ZStack {
                            GlobalCardAppearance
                            if displayTracks[index].minimumSpeed == 0 && displayTracks[index].maximumSpeed == 0 {
                                HStack(alignment: .center, spacing: 0) {
                                    Text(displayTracks[index].displayName)
                                        .font(.system(size: 35, weight: .semibold))
                                        .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                        .minimumScaleFactor(0.3)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                        .foregroundColor(.white)
                                        .padding(.leading, 16)
                                    Spacer()
                                    AudioBarsView(isPlaying: audioController.isSoundtrackPlaying, currentSoundtrackTitle: displayedTitle)
                                        .frame(width: 70, height: 50)
                                        .padding(.trailing, 16)
                                }
                            } else {
                                ZStack(alignment: .topLeading) {
                                    VStack(spacing: 4) {
                                        Text(displayTracks[index].displayName)
                                            .font(.system(size: 35, weight: .semibold))
                                            .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                            .minimumScaleFactor(0.3)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)
                                            .foregroundColor(.white)
                                            .padding(.leading, 16)
                                            .offset(x: -41, y: 12)
                                        
                                        HStack(spacing: 8) {
                                            Text("\(displayTracks[index].minimumSpeed)")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white.opacity(0.5))
                                                .scaleEffect(minSpeedScale[index] ?? 1.0)
                                            Gauge(value: isCurrentSoundtrack ? Double(audioController.calculateVolumeForTrack(at: index, speed: locationHandler.speedMPH)) : 0.0,
                                                  in: 0...Double(mapVolume(displayTracks[index].maximumVolume))) {
                                                EmptyView()
                                            }
                                            .gaugeStyle(.linearCapacity)
                                            .tint(.gray)
                                            .frame(width: geometry.size.width * 0.69, height: 10)
                                            .animation(.easeInOut(duration: 1.0), value: isCurrentSoundtrack ? locationHandler.speedMPH : 0.0)
                                            Text("\(displayTracks[index].maximumSpeed)")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white.opacity(0.5))
                                                .scaleEffect(maxSpeedScale[index] ?? 1.0)
                                        }
                                        .padding(.horizontal, 16)
                                        .offset(y: 20)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    
                                    AudioBarsView(isPlaying: audioController.isSoundtrackPlaying, currentSoundtrackTitle: displayedTitle)
                                        .frame(width: 70, height: 50)
                                        .padding(.trailing, 16)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                        .offset(y: 14)
                                }
                            }
                        }
                    }
                    .frame(height: 108)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    @ViewBuilder
    private func playbackButtons() -> some View {
        VStack {
            Spacer()
            HStack(spacing: 80) {
                if audioController.isSoundtrackPlaying {
                    // Clock button when playing
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isClockActive.toggle()
                        }
                    }) {
                        Image(systemName: "clock.badge.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isClockActive ? .red : .white)
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(isClockActive ? .white : .clear).interactive())

                    }
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
            }
           // .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color.clear)
        }
    }
}


