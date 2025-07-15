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
            infoPage()
        }
        .alert(isPresented: $showLengthMismatchAlert) {
            Alert(
                title: Text("Length Mismatch"),
                message: Text("All tracks should be the same length"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: Info Page
    private func infoPage() -> some View {
        Color(red: 26/255, green: 20/255, blue: 26/255)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                VStack(alignment: .leading, spacing: 20) {
                    Text("For best results...")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundColor(.white)
                    Text("All tracks must be the same length")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("All uploaded tracks must be the same length as the base track. This is so the audio files loop cleanly.")
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                    Text("Use different instruments")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    HStack {
                        Text("I recommend using this tool to separate audio tracks. It uses AI to separate the voice, drums, bass, etc. (Please note that the tool isn't owned by me and I don't have any authority over its use.)")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://uvronline.app/ai?hp&px30ac9k6taj1r&lev3n") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Image(systemName: "link")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    Spacer()
                }
                .padding()
            )
    }

    // MARK: Base Audio Stack
    private var baseAudioStack: some View {
        GeometryReader { geometry in
            baseAudioCard(geometry: geometry)
                .offset(x: createBaseOffset)
                .gesture(baseAudioGesture)
        }
        .frame(height: 108)
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
            .sheet(isPresented: $createBaseShowingFilePicker, content: baseAudioPicker)
        }
    }

    private var baseAudioGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                createBaseOffset = value.translation.width
            }
            .onEnded { value in
                if value.translation.width < -50 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        createBaseOffset = -UIScreen.main.bounds.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let url = createBaseAudioURL {
                            removeAudioFile(at: url)
                        }
                        if createBaseIsPlaying, let player = createBasePlayer {
                            player.pause()
                            createBaseIsPlaying = false
                        }
                        createBaseAudioURL = nil
                        createBasePlayer = nil
                        createBaseOffset = 0
                        createBaseVolume = 0.0
                        createBaseTitle = "Base"
                        if createAdditionalZStacks.isEmpty {
                            createReferenceLength = nil
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        createBaseOffset = 0
                    }
                }
            }
    }

    private func baseAudioPicker() -> some View {
        DocumentPicker { url in
            if let storedURL = storeAudioFile(url, name: "Soundtrack\(soundtracks.count + 1)Base_\(UUID().uuidString)") {
                if let tempPlayer = try? AVAudioPlayer(contentsOf: storedURL) {
                    let duration = tempPlayer.duration
                    if createReferenceLength == nil || createAdditionalZStacks.isEmpty {
                        createReferenceLength = duration
                        createBaseAudioURL = storedURL
                        createBasePlayer = tempPlayer
                        createBasePlayer?.volume = mapVolume(createBaseVolume)
                        createBasePlayer?.prepareToPlay()
                    } else if abs(duration - createReferenceLength!) < 0.1 {
                        createBaseAudioURL = storedURL
                        createBasePlayer = tempPlayer
                        createBasePlayer?.volume = mapVolume(createBaseVolume)
                        createBasePlayer?.prepareToPlay()
                    } else {
                        removeAudioFile(at: storedURL)
                        showLengthMismatchAlert = true
                    }
                }
            }
        }
    }

    // MARK: Dynamic Audio Stacks
    private var dynamicAudioStacks: some View {
        ForEach(createAdditionalZStacks.indices, id: \ .self) { index in
            GeometryReader { geometry in
                dynamicAudioCard(geometry: geometry, index: index)
                    .offset(x: createAdditionalZStacks[index].offset)
                    .gesture(dynamicAudioGesture(index: index))
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
            .sheet(isPresented: Binding(get: { createAdditionalZStacks[index].showingFilePicker }, set: { newValue in createAdditionalZStacks[index].showingFilePicker = newValue })) {
                dynamicAudioPicker(index: index)
            }
        }
    }

    private func dynamicAudioGesture(index: Int) -> some Gesture {
        DragGesture()
            .onChanged { value in
                createAdditionalZStacks[index].offset = value.translation.width
            }
            .onEnded { value in
                if value.translation.width < -50 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        createAdditionalZStacks[index].offset = -UIScreen.main.bounds.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let url = createAdditionalZStacks[index].audioURL {
                            removeAudioFile(at: url)
                        }
                        if createAdditionalZStacks[index].isPlaying, let player = createAdditionalZStacks[index].player {
                            player.pause()
                            createAdditionalZStacks[index].isPlaying = false
                        }
                        createAdditionalZStacks.remove(at: index)
                        if index < createAdditionalTitles.count {
                            createAdditionalTitles.remove(at: index)
                            createAdditionalAlwaysPlaying.remove(at: index)
                        }
                        if createAdditionalZStacks.isEmpty && createBaseAudioURL == nil {
                            createReferenceLength = nil
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        createAdditionalZStacks[index].offset = 0
                    }
                }
            }
    }

    private func dynamicAudioPicker(index: Int) -> some View {
        DocumentPicker { url in
            if let storedURL = storeAudioFile(url, name: "Soundtrack\(soundtracks.count + 1)Audio\(index + 1)_\(UUID().uuidString)") {
                if let tempPlayer = try? AVAudioPlayer(contentsOf: storedURL) {
                    let duration = tempPlayer.duration
                    if createReferenceLength == nil || abs(duration - createReferenceLength!) < 0.1 {
                        createAdditionalZStacks[index].audioURL = storedURL
                        createAdditionalZStacks[index].player = tempPlayer
                        createAdditionalZStacks[index].player?.volume = mapVolume(createAdditionalZStacks[index].volume)
                        createAdditionalZStacks[index].player?.prepareToPlay()
                        if createReferenceLength == nil {
                            createReferenceLength = duration
                        }
                    } else {
                        removeAudioFile(at: storedURL)
                        showLengthMismatchAlert = true
                    }
                }
            }
        }
    }

    // MARK: Add Audio Button
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

    // MARK: Audio Helpers
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

    private func storeAudioFile(_ url: URL, name: String) -> URL? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to access documents directory")
            return nil
        }
        let destinationURL = documentsDirectory.appendingPathComponent("\(name).mp3")
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
            return destinationURL
        } catch {
            print("Error storing audio file: \(error)")
            return nil
        }
    }

    private func removeAudioFile(at url: URL) {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                print("Removed audio file at: \(url.path)")
            }
        } catch {
            print("Error removing audio file: \(error)")
        }
    }

    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
    }
} 
