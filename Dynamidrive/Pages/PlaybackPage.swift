import SwiftUI
import AVFoundation
import MediaPlayer
import MapKit

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
    
    @State private var minSpeedScale: [Int: CGFloat] = [:]
    @State private var maxSpeedScale: [Int: CGFloat] = [:]
    @State private var minSpeedBelow: [Int: Bool] = [:]
    @State private var maxSpeedBelow: [Int: Bool] = [:]
    
    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
    }
    
    private func prepareForSharing() -> [Any] {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let soundtrack = pendingSoundtrack ?? Soundtrack(id: UUID(), title: audioController.currentSoundtrackTitle, tracks: audioController.currentTracks, players: audioController.currentPlayers)
        
        let soundtrackFolder = documentsDirectory.appendingPathComponent(soundtrack.title)
        try? fileManager.createDirectory(at: soundtrackFolder, withIntermediateDirectories: true, attributes: nil)
        
        var audioFiles: [URL] = []
        for track in soundtrack.tracks {
            let sourceURL = documentsDirectory.appendingPathComponent(track.audioFileName)
            let destinationURL = soundtrackFolder.appendingPathComponent(track.audioFileName)
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
            audioFiles.append(destinationURL)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(soundtrack) {
            let jsonURL = soundtrackFolder.appendingPathComponent("soundtrack.json")
            try? data.write(to: jsonURL)
            audioFiles.append(jsonURL)
        }
        
        return [soundtrackFolder]
    }
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if isCompactHeight {
                    // Compact view with only playback controls
                    HStack {
                        Spacer()
                        VStack {
                            if currentHeight > 100 && currentHeight <= 150 {
                            
                                Text(pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle)
                                    .font(.system(size: 35, weight: .bold))
                                    .foregroundColor(.white)
                                    
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.8)
                                    .padding(.top, 30)
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
                        ScrollView(.vertical, showsIndicators: false) {
                            trackList()
                                .padding(.horizontal)
                                .padding(.top, 140)
                                .padding(.bottom, 140)
                        }
                        .ignoresSafeArea()

                        VStack(spacing: 20) {
                            // Header
                            HStack {
                                Text(pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle)
                                    .font(.system(size: 35, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {
                                    showShareSheet = true
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .frame(width: 30, height: 30)
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
            .sheet(isPresented: $showShareSheet) {
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
                Text("\(displayedSpeed)")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 40, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.default, value: displayedSpeed)
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
                                            Gauge(value: Double(audioController.calculateVolumeForTrack(at: index, speed: locationHandler.speedMPH)),
                                                  in: 0...Double(mapVolume(displayTracks[index].maximumVolume))) {
                                                EmptyView()
                                            }
                                            .gaugeStyle(.linearCapacity)
                                            .tint(.gray)
                                            .frame(width: geometry.size.width * 0.69, height: 10)
                                            .animation(.easeInOut(duration: 1.0), value: locationHandler.speedMPH)
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
                
                Button(action: {
                    if let pending = pendingSoundtrack, audioController.currentSoundtrackTitle != pending.title {
                        if audioController.isSoundtrackPlaying {
                            audioController.toggleSoundtrackPlayback()
                        }
                        audioController.setCurrentSoundtrack(tracks: pending.tracks, players: pending.players, title: pending.title)
                        audioController.toggleSoundtrackPlayback()
                    } else {
                        audioController.toggleSoundtrackPlayback()
                    }
                }) {
                    Image(systemName: audioController.isSoundtrackPlaying ? "pause.fill" : "play.fill")
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
