//  ↓↓
// READ <<<<<----- All elements of this page are found in ContentView.swift from line 875!! 😡😡😡😡😭😭😭😭🙏🙏🙏🙏🙏
// ^^^^

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit

struct CreatePage: View {
    @Binding var showCreatePage: Bool
    @Binding var showConfigurePage: Bool
    @Binding var showVolumePage: Bool
    @Binding var createBaseAudioURL: URL?
    @Binding var createBasePlayer: AVAudioPlayer?
    @Binding var createBaseIsPlaying: Bool
    @Binding var createBaseOffset: CGFloat
    @Binding var createBaseShowingFilePicker: Bool
    @Binding var createBaseVolume: Float
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
    @Binding var gradientRotation: Double
    @Binding var showInfoPage: Bool
    @Binding var currentPage: AppPage
    @Binding var previousPage: AppPage?
    @Binding var createTip: CreatePageTip
    @EnvironmentObject private var audioController: AudioController
    @Binding var showLengthMismatchAlert: Bool
    @Binding var soundtracks: [Soundtrack]
    // Add any other bindings needed for full functionality

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 40) {
                    HStack {
                        Text(createSoundtrackTitle)
                            .font(.system(size: 35, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            showInfoPage = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                        }
                    }
                    VStack(spacing: 10) {
                        baseAudioStack
                        dynamicAudioStacks
                        addAudioButton
                    }
                    Spacer().frame(height: 100)
                }
                .padding()
                .offset(y: -15)
            }
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        pauseAllAudio()
                        showCreatePage = false
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .globalButtonStyle()
                    }
                    Button(action: {
                        if createBaseAudioURL != nil && createAdditionalZStacks.contains(where: { $0.audioURL != nil }) {
                            showConfigurePage = true
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }) {
                        Image(systemName: "arrow.forward")
                            .globalButtonStyle()
                    }
                    .opacity(createBaseAudioURL != nil && createAdditionalZStacks.contains(where: { $0.audioURL != nil }) ? 1.0 : 0.5)
                    ZStack {
                        Image("Gradient")
                            .resizable()
                            .scaledToFit()
                            .opacity(1)
                            .frame(width: 115, height: 115)
                            .rotationEffect(.degrees(gradientRotation))
                            .onAppear {
                                gradientRotation = 0
                                withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                                    gradientRotation = 360
                                }
                            }
                            .onDisappear {
                                gradientRotation = 0
                            }
                        Button(action: {
                            showAIUploadPage = true
                            currentPage = .aiUpload
                            previousPage = .create
                        }) {
                            Image(systemName: "sparkles")
                                .globalButtonStyle()
                        }
                        .popoverTip(createTip, arrowEdge: .bottom)
                    }
                    .frame(width: 50, height: 50)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
        .sheet(isPresented: $showInfoPage) {
            // Provide your infoPage view here
            EmptyView()
        }
    }

    private var baseAudioStack: some View {
        GeometryReader { geometry in
            baseAudioCard(geometry: geometry)
                .offset(x: createBaseOffset)
                // .gesture(baseAudioGesture) // Add if you want swipe-to-remove
        }
        .frame(height: 108)
        .alert(isPresented: $showLengthMismatchAlert) {
            Alert(
                title: Text("Length Mismatch"),
                message: Text("All tracks should be the same length"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func baseAudioCard(geometry: GeometryProxy) -> some View {
        ZStack {
            GlobalCardAppearance
            Text(createBaseTitle)
                .font(.system(size: 35, weight: .semibold))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                .minimumScaleFactor(0.3)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .offset(x:-40)
                .foregroundColor(.white)
                .padding(.leading, 16)
            Button(action: {
                if createBaseAudioURL == nil {
                    createBaseShowingFilePicker = true
                } else {
                    toggleBasePlayback()
                }
            }) {
                Image(systemName: createBaseAudioURL == nil ? "document.badge.plus.fill" : (createBaseIsPlaying ? "pause.fill" : "play.fill"))
                    .globalButtonStyle()
                    .offset(x: createBaseAudioURL == nil ? 1.5 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            // .sheet(isPresented: $createBaseShowingFilePicker, content: baseAudioPicker) // Add picker if needed
        }
    }

    private var dynamicAudioStacks: some View {
        ForEach(createAdditionalZStacks.indices, id: \ .self) { index in
            GeometryReader { geometry in
                dynamicAudioCard(geometry: geometry, index: index)
                    .offset(x: createAdditionalZStacks[index].offset)
                    // .gesture(dynamicAudioGesture(index: index)) // Add if you want swipe-to-remove
            }
            .frame(height: 108)
        }
    }

    private func dynamicAudioCard(geometry: GeometryProxy, index: Int) -> some View {
        ZStack {
            GlobalCardAppearance
            Text(index < createAdditionalTitles.count ? createAdditionalTitles[index] : "Audio \(index + 1)")
                .font(.system(size: 35, weight: .semibold))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                .minimumScaleFactor(0.3)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .offset(x:-40)
                .foregroundColor(.white)
                .padding(.leading, 16)
            Button(action: {
                if createAdditionalZStacks[index].audioURL == nil {
                    createAdditionalZStacks[index].showingFilePicker = true
                } else {
                    togglePlayback(at: index)
                }
            }) {
                Image(systemName: createAdditionalZStacks[index].audioURL == nil ? "document.badge.plus.fill" : (createAdditionalZStacks[index].isPlaying ? "pause.fill" : "play.fill"))
                    .globalButtonStyle()
                    .offset(x: createBaseAudioURL == nil ? 1.5 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            // .sheet(isPresented: Binding(get: { createAdditionalZStacks[index].showingFilePicker }, set: { newValue in createAdditionalZStacks[index].showingFilePicker = newValue })) { dynamicAudioPicker(index: index) }
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
                    .globalButtonStyle()
            }
        }
        .padding(.top, 10)
    }

    private func pauseAllAudio() {
        if createBaseIsPlaying, let player = createBasePlayer {
            player.pause()
            createBaseIsPlaying = false
        }
        for index in createAdditionalZStacks.indices {
            if createAdditionalZStacks[index].isPlaying, let player = createAdditionalZStacks[index].player {
                player.pause()
                createAdditionalZStacks[index].isPlaying = false
            }
        }
        // stopPreviewTrackingTimer() // Add if you want preview timer logic
    }

    private func toggleBasePlayback() {
        guard let player = createBasePlayer else { return }
        if createBaseIsPlaying {
            player.pause()
            createBaseIsPlaying = false
            // Add preview timer logic if needed
        } else {
            // Add logic to stop soundtrack playback if needed
            player.play()
            createBaseIsPlaying = true
            // Add preview timer logic if needed
        }
    }

    private func togglePlayback(at index: Int) {
        guard let player = createAdditionalZStacks[index].player else { return }
        if createAdditionalZStacks[index].isPlaying {
            player.pause()
            createAdditionalZStacks[index].isPlaying = false
            // Add preview timer logic if needed
        } else {
            // Add logic to stop soundtrack playback if needed
            player.play()
            createAdditionalZStacks[index].isPlaying = true
            // Add preview timer logic if needed
        }
    }
} 
