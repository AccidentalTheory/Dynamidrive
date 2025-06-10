import SwiftUI
import AVFoundation

struct VolumeScreen: View {
    @Binding var showVolumePage: Bool
    @Binding var createBaseTitle: String
    @Binding var createBaseVolume: Float
    @Binding var createBaseAudioURL: URL?
    @Binding var createBasePlayer: AVAudioPlayer?
    @Binding var createAdditionalZStacks: [ContentView.ZStackData]
    @Binding var createAdditionalTitles: [String]
    
    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Volume Control")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            VStack(spacing: 10) {
                if createBaseAudioURL != nil {
                    GeometryReader { geometry in
                        ZStack {
                            Color(red: 0/255, green: 0/255, blue: 0/255)
                                .opacity(0.3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                        )
                                .frame(width: geometry.size.width, height: 108)
                                .cornerRadius(16)
                                .clipped()
                            VStack(spacing: 4) {
                                Text(createBaseTitle)
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 16)
                                Slider(value: $createBaseVolume, in: -100...100, step: 1) { _ in
                                    if let player = createBasePlayer {
                                        player.volume = mapVolume(createBaseVolume)
                                    }
                                }
                                .frame(width: geometry.size.width * 0.7)
                            }
                        }
                    }
                    .frame(height: 108)
                }
                ForEach(createAdditionalZStacks.indices, id: \.self) { index in
                    if createAdditionalZStacks[index].audioURL != nil {
                        GeometryReader { geometry in
                            ZStack {
                                Color(red: 20/255, green: 20/255, blue: 20/255)
                                    .frame(width: geometry.size.width, height: 108)
                                    .cornerRadius(16)
                                    .clipped()
                                VStack(spacing: 4) {
                                    Text(index < createAdditionalTitles.count ? createAdditionalTitles[index] : "Audio \(index + 1)")
                                        .font(.system(size: 35, weight: .semibold))
                                        .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                        .minimumScaleFactor(0.3)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                        .offset(x:-40)
                                        .foregroundColor(.white)
                                        .padding(.leading, 16)
                                    Slider(value: Binding(
                                        get: { createAdditionalZStacks[index].volume },
                                        set: { createAdditionalZStacks[index].volume = $0 }
                                    ), in: -100...100, step: 1) { _ in
                                        if let player = createAdditionalZStacks[index].player {
                                            player.volume = mapVolume(createAdditionalZStacks[index].volume)
                                        }
                                    }
                                    .frame(width: geometry.size.width * 0.7)
                                }
                            }
                        }
                        .frame(height: 108)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .overlay(
            Button(action: {
                showVolumePage = false
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding()
        )
        .zIndex(4)
    }
} 