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

// Audio controls container
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
                }
            }
        }
    }
}

struct VolumeScreen: View {
    @Binding var showVolumePage: Bool
    @Binding var createBaseTitle: String
    @Binding var createBaseVolume: Double
    @Binding var createBaseAudioURL: URL?
    @Binding var createBasePlayer: AVAudioPlayer?
    @Binding var createAdditionalZStacks: [ZStackData]
    @Binding var createAdditionalTitles: [String]
    
    private var headerView: some View {
        HStack {
            Text("Volume Control")
                .font(.system(size: 35, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
    }
    
    private var backButton: some View {
        Button(action: {
            showVolumePage = false
        }) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
               
                .clipShape(Circle())
                .glassEffect(.regular.tint(.clear).interactive())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding()
    }
    
    var body: some View {
        VStack(spacing: 20) {
            headerView
            AudioControlsView(
                createBaseAudioURL: $createBaseAudioURL,
                createBaseTitle: $createBaseTitle,
                createBaseVolume: $createBaseVolume,
                createBasePlayer: $createBasePlayer,
                createAdditionalZStacks: $createAdditionalZStacks,
                createAdditionalTitles: $createAdditionalTitles
            )
            Spacer()
        }
        .padding()
        .overlay(backButton)
        .zIndex(4)
    }
}
