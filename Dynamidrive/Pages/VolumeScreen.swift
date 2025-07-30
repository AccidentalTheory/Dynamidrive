import SwiftUI
import AVFoundation

// Base audio control component
struct BaseAudioControl: View {
    @Binding var title: String
    @Binding var volume: Double
    var player: AVAudioPlayer?
    let geometry: GeometryProxy
    
    private func mapVolume(_ percentage: Double) -> Float {
        let mapped = Float((percentage + 100) / 100)
        return max(0.0, min(2.0, mapped))
    }
    
    var body: some View {
        ZStack {
            GlobalCardAppearance
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                Slider(value: $volume, in: -100...100, step: 1) { _ in
                    if let player = player {
                        player.volume = mapVolume(volume)
                    }
                }
                .frame(width: geometry.size.width * 0.7)
            }
        }
    }
}

// Additional audio control component
struct AdditionalAudioControl: View {
    let index: Int
    @Binding var stack: ZStackData
    let geometry: GeometryProxy
    @Binding var titles: [String]
    
    private func mapVolume(_ percentage: Double) -> Float {
        let mapped = Float((percentage + 100) / 100)
        return max(0.0, min(2.0, mapped))
    }
    
    var body: some View {
        ZStack {
            GlobalCardAppearance
        
            VStack(spacing: 4) {
                Text(index < titles.count ? titles[index] : "Audio \(index + 1)")
                    .font(.system(size: 35, weight: .semibold))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                    .minimumScaleFactor(0.3)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .offset(x:-40)
                    .foregroundColor(.white)
                    .padding(.leading, 16)
                Slider(value: Binding(
                    get: { Double(stack.volume) },
                    set: { stack.volume = Float($0) }
                ), in: -100...100, step: 1) { _ in
                    if let player = stack.player {
                        player.volume = mapVolume(Double(stack.volume))
                    }
                }
                .frame(width: geometry.size.width * 0.7)
            }
        }
    }
}

// Existing soundtrack audio control component
struct ExistingTrackAudioControl: View {
    let index: Int
    @Binding var track: AudioController.SoundtrackData
    let geometry: GeometryProxy
    @EnvironmentObject private var audioController: AudioController
    
    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
    }
    
    private func unmapVolume(_ mapped: Float) -> Float {
        return (mapped * 100) - 100
    }
    
    var body: some View {
        ZStack {
            GlobalCardAppearance
        
            VStack(spacing: 4) {
                Text(track.displayName)
                    .font(.system(size: 35, weight: .semibold))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                    .minimumScaleFactor(0.3)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .offset(x:-40)
                    .foregroundColor(.white)
                    .padding(.leading, 16)
                Slider(value: Binding(
                    get: { Double(unmapVolume(track.maximumVolume)) },
                    set: { newValue in
                        track.maximumVolume = mapVolume(Float(newValue))
                        // Update the audio controller's current tracks
                        if index < audioController.currentTracks.count {
                            audioController.currentTracks[index].maximumVolume = track.maximumVolume
                        }
                        // Adjust volumes for current speed
                        audioController.adjustVolumesForSpeed(audioController.locationHandler.speedMPH)
                    }
                ), in: -100...100, step: 1)
                .frame(width: geometry.size.width * 0.7)
            }
        }
    }
}

// Audio controls container for creation flow
struct AudioControlsView: View {
    @Binding var createBaseAudioURL: URL?
    @Binding var createBaseTitle: String
    @Binding var createBaseVolume: Double
    @Binding var createBasePlayer: AVAudioPlayer?
    @Binding var createAdditionalZStacks: [ZStackData]
    @Binding var createAdditionalTitles: [String]
    
    var body: some View {
        VStack(spacing: 10) {
            if createBaseAudioURL != nil {
                GeometryReader { geometry in
                    BaseAudioControl(
                        title: $createBaseTitle,
                        volume: $createBaseVolume,
                        player: createBasePlayer,
                        geometry: geometry
                    )
                }
                .frame(height: 108)
                .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
            }
            ForEach(Array(createAdditionalZStacks.enumerated()), id: \.element.id) { index, stack in
                if stack.audioURL != nil {
                    GeometryReader { geometry in
                        AdditionalAudioControl(
                            index: index,
                            stack: $createAdditionalZStacks[index],
                            geometry: geometry,
                            titles: $createAdditionalTitles
                        )
                    }
                    .frame(height: 108)
                    .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
                }
            }
        }
    }
}

// Audio controls container for existing soundtracks
struct ExistingSoundtrackAudioControlsView: View {
    @Binding var tracks: [AudioController.SoundtrackData]
    
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                GeometryReader { geometry in
                    ExistingTrackAudioControl(
                        index: index,
                        track: $tracks[index],
                        geometry: geometry
                    )
                }
                .frame(height: 108)
                .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
            }
        }
    }
}

struct VolumeScreen: View {
    @Binding var showVolumePage: Bool
    @Binding var volumePageSource: AppPage?
    @Binding var createBaseTitle: String
    @Binding var createBaseVolume: Double
    @Binding var createBaseAudioURL: URL?
    @Binding var createBasePlayer: AVAudioPlayer?
    @Binding var createAdditionalZStacks: [ZStackData]
    @Binding var createAdditionalTitles: [String]
    
    // For editing existing soundtracks
    @EnvironmentObject private var audioController: AudioController
    @State private var editingTracks: [AudioController.SoundtrackData] = []
    
    var body: some View {
        PageLayout(
            title: "Volume",
            leftButtonAction: {},
            rightButtonAction: {},
            leftButtonSymbol: "",
            rightButtonSymbol: "",
            bottomButtons: [
                PageButton(label: { Image(systemName: "arrow.uturn.backward").globalButtonStyle() }, action: {
                    print("[VolumeScreen] Back button pressed, current source: \(volumePageSource.map { String(describing: $0) } ?? "nil")")
                    showVolumePage = false
                })
            ]
        ) {
            VStack(spacing: 20) {
                // Show different controls based on the source
                if volumePageSource == .edit {
                    // For editing existing soundtracks
                    ExistingSoundtrackAudioControlsView(tracks: $editingTracks)
                } else {
                    // For creation flow
                    AudioControlsView(
                        createBaseAudioURL: $createBaseAudioURL,
                        createBaseTitle: $createBaseTitle,
                        createBaseVolume: $createBaseVolume,
                        createBasePlayer: $createBasePlayer,
                        createAdditionalZStacks: $createAdditionalZStacks,
                        createAdditionalTitles: $createAdditionalTitles
                    )
                }
                
                Spacer().frame(height: 100)
            }
        }
        .onAppear {
            // Initialize editing tracks if coming from edit page
            if volumePageSource == .edit {
                editingTracks = audioController.currentTracks
            }
        }
    }
}
