//  ↓↓
// READ <<<<<----- All elements of this page are found in ContentView.swift from line 875!! 😡😡😡😡😭😭😭😭🙏🙏🙏🙏🙏
// ^^^^

import SwiftUI
import AVFoundation

struct CreatePage: View {
    @Binding var showCreatePage: Bool
    @Binding var showConfigurePage: Bool
    @Binding var showVolumePage: Bool
    @Binding var createBaseAudioURL: URL?
    @Binding var createBasePlayer: AVAudioPlayer?
    @Binding var createBaseIsPlaying: Bool 
    @Binding var createBaseOffset: CGFloat
    @Binding var createBaseShowingFilePicker: Bool
    @Binding var createBaseVolume: Double
    @Binding var createBaseTitle: String
    @Binding var createAdditionalZStacks: [ZStackData]
    @Binding var createAdditionalTitles: [String]
    @Binding var createAdditionalAlwaysPlaying: [Bool]
    @Binding var createSoundtrackTitle: String
    @Binding var createReferenceLength: TimeInterval?
    @Binding var createNextID: Int
    @Binding var createAudio1MinimumSpeed: Int
    @Binding var createAudio1MaximumSpeed: Int
    @Binding var showAIUploadPage: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 40) {
                        HStack {
                            Text(createSoundtrackTitle)
                                .font(.system(size: 35, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        VStack(spacing: 10) {
                            baseAudioStack
                            dynamicAudioStacks
                            addAudioButton
                        }
                        Spacer().frame(height: 100)
                    }
                    .padding()
                }
                
                // Fixed bottom controls
                VStack {
                    Spacer()
                    HStack(spacing: 80) {
                        Button(action: {
                            showCreatePage = false
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        
                        Button(action: {
                            showVolumePage = true
                        }) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        
                        Button(action: {
                            showConfigurePage = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
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
    
    private var baseAudioStack: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    )
                    .frame(width: geometry.size.width, height: 108)
                    .cornerRadius(16)
                    .clipped()
                Text(createBaseTitle)
                    .font(.system(size: 35, weight: .semibold))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                    .minimumScaleFactor(0.3)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .offset(x: -40)
                    .foregroundColor(.white)
                    .padding(.leading, 16)
                Button(action: {
                    if createBaseAudioURL == nil {
                        createBaseShowingFilePicker = true
                    } else {
                        toggleBasePlayback()
                    }
                }) {
                    Image(systemName: createBaseAudioURL == nil ? "plus" : (createBaseIsPlaying ? "pause" : "play"))
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
            }
        }
        .frame(height: 108)
    }
    
    private var dynamicAudioStacks: some View {
        ForEach(createAdditionalZStacks.indices, id: \.self) { index in
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.3), lineWidth: 3)
                        )
                        .frame(width: geometry.size.width, height: 108)
                        .cornerRadius(16)
                        .clipped()
                    Text(createAdditionalTitles[index])
                        .font(.system(size: 35, weight: .semibold))
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                        .minimumScaleFactor(0.3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .offset(x: -40)
                        .foregroundColor(.white)
                        .padding(.leading, 16)
                    Button(action: {
                        if createAdditionalZStacks[index].audioURL == nil {
                            createAdditionalZStacks[index].showingFilePicker = true
                        } else {
                            togglePlayback(at: index)
                        }
                    }) {
                        Image(systemName: createAdditionalZStacks[index].audioURL == nil ? "plus" : (createAdditionalZStacks[index].isPlaying ? "pause" : "play"))
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)
                }
            }
            .frame(height: 108)
        }
    }
    
    private var addAudioButton: some View {
        HStack(spacing: 20) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    createAdditionalZStacks.append(ZStackData(id: createNextID))
                    createAdditionalTitles.append("Audio \(createNextID)")
                    createAdditionalAlwaysPlaying.append(false)
                    createNextID += 1
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            
            Button(action: {
                showAIUploadPage = true
            }) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .padding(.top, 10)
    }
    
    private func toggleBasePlayback() {
        guard let player = createBasePlayer else { return }
        if createBaseIsPlaying {
            player.pause()
            createBaseIsPlaying = false
        } else {
            player.play()
            createBaseIsPlaying = true
        }
    }
    
    private func togglePlayback(at index: Int) {
        guard let player = createAdditionalZStacks[index].player else { return }
        if createAdditionalZStacks[index].isPlaying {
            player.pause()
            createAdditionalZStacks[index].isPlaying = false
        } else {
            player.play()
            createAdditionalZStacks[index].isPlaying = true
        }
    }
} 
