

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import ZIPFoundation
 // If needed, or use relative import if in same module

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
    var saveSoundtracks: () -> Void // Add this parameter
    @State private var showImportPicker = false
    @State private var importZipURL: URL? = nil
    // Import system state
    @State private var importSoundtrackTitle: String = ""
    @State private var importTracks: [ImportTrack] = []
    @State private var importTempFolder: URL? = nil
    @State private var importError: String? = nil
    // Add back the local state for the sheet:
    @State private var showImportConfirmation = false

    private struct ParsedTrack {
        let displayName: String
        let fileName: String
        let minSpeed: Int
        let maxSpeed: Int
        let volume: Float
    }
    // Add any other bindings needed for full functionality

    var body: some View {
        PageLayout(
            title: "Create New",
            leftButtonAction: { showImportPicker = true },
            rightButtonAction: { showInfoPage = true },
            leftButtonSymbol: "square.and.arrow.down",
            rightButtonSymbol: "info",
            bottomButtons: [
                PageButton(label: { Image(systemName: "arrow.uturn.backward").globalButtonStyle() }, action: {
                    pauseAllAudio()
                    showCreatePage = false
                }),
                PageButton(label: { Image(systemName: "arrow.forward").globalButtonStyle() }, action: {
                    if createBaseAudioURL != nil && createAdditionalZStacks.contains(where: { $0.audioURL != nil }) {
                        showConfigurePage = true
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }),
                PageButton(label: {
                    Image(systemName: "sparkles").globalButtonStyle()
                }, action: {
                    showAIUploadPage = true
                    currentPage = .aiUpload
                    previousPage = .create
                })
            ]
        ) {
            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    baseAudioStack
                    dynamicAudioStacks
                    addAudioButton
                }
                Spacer().frame(height: 100)
            }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPicker(onPick: { url in
                print("Picked zip file: \(url)")
                importZipURL = url
                handleImportZip(url)
            })
        }
        .sheet(isPresented: $showInfoPage) {
            infoPage()
        }
        .alert(isPresented: Binding<Bool>(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Alert(title: Text("Import Error"), message: Text(importError ?? "Unknown error"), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showImportConfirmation) {
            ImportConfirmationPage(
                soundtrackTitle: importSoundtrackTitle,
                tracks: importTracks,
                onCancel: {
                    for t in importTracks { t.player?.stop() }
                    if let temp = importTempFolder { try? FileManager.default.removeItem(at: temp) }
                    importTracks = []
                    importSoundtrackTitle = ""
                    importTempFolder = nil
                    showImportConfirmation = false
                },
                onImport: { selectedColor in 
                    do {
                        let fileManager = FileManager.default
                        guard let tempFolder = importTempFolder else { return }
                        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                        var newTracks: [AudioController.SoundtrackData] = []
                        for t in importTracks {
                            let newFileName = "Soundtrack\(soundtracks.count + 1)_\(t.displayName)_\(UUID().uuidString).mp3"
                            let destURL = documentsDirectory.appendingPathComponent(newFileName)
                            try? fileManager.copyItem(at: t.fileURL, to: destURL)
                            newTracks.append(AudioController.SoundtrackData(
                                audioFileName: newFileName,
                                displayName: t.displayName,
                                maximumVolume: t.volume,
                                minimumSpeed: t.minSpeed,
                                maximumSpeed: t.maxSpeed
                            ))
                        }
                        let players = newTracks.map { track in
                            try? AVAudioPlayer(contentsOf: documentsDirectory.appendingPathComponent(track.audioFileName))
                        }
                        soundtracks.append(Soundtrack(id: UUID(), title: importSoundtrackTitle, tracks: newTracks, players: players, cardColor: selectedColor))
                        for t in importTracks { t.player?.stop() }
                        if let temp = importTempFolder { try? fileManager.removeItem(at: temp) }
                        importTracks = []
                        importSoundtrackTitle = ""
                        importTempFolder = nil
                        showImportConfirmation = false
                        currentPage = .main
                        saveSoundtracks() // Call the saveSoundtracks closure
                    } catch {
                        importError = "Failed to import soundtrack: \(error.localizedDescription)"
                    }
                }
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
        .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
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
                if createBaseAudioURL == nil {
                    Image(systemName: "document.badge.plus.fill")
                        .offset(x: 1.5)
                        .globalButtonStyle()
                        
                } else {
                    Image(systemName: createBaseIsPlaying ? "pause.fill" : "play.fill")
                        .globalButtonStyle()
                }
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
        AudioDocumentPicker { url in
            if let storedURL = storeAudioFile(url, name: "Soundtrack\(soundtracks.count + 1)Base_\(UUID().uuidString)") {
                if let tempPlayer = try? AVAudioPlayer(contentsOf: storedURL) {
                    let duration = tempPlayer.duration
                    let fileName = url.deletingPathExtension().lastPathComponent
                    if createReferenceLength == nil || createAdditionalZStacks.isEmpty {
                        createReferenceLength = duration
                        createBaseAudioURL = storedURL
                        createBasePlayer = tempPlayer
                        createBasePlayer?.volume = mapVolume(createBaseVolume)
                        createBasePlayer?.prepareToPlay()
                        createBaseTitle = fileName // Set base title to file name
                    } else if abs(duration - createReferenceLength!) < 0.1 {
                        createBaseAudioURL = storedURL
                        createBasePlayer = tempPlayer
                        createBasePlayer?.volume = mapVolume(createBaseVolume)
                        createBasePlayer?.prepareToPlay()
                        createBaseTitle = fileName // Set base title to file name
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
            .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
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
                if createAdditionalZStacks[index].audioURL == nil {
                    Image(systemName: "document.badge.plus.fill")
                        .offset(x: 1.5)
                        .globalButtonStyle()
                        
                } else {
                    Image(systemName: createAdditionalZStacks[index].isPlaying ? "pause.fill" : "play.fill")
                        .globalButtonStyle()
                }
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
        AudioDocumentPicker { url in
            if let storedURL = storeAudioFile(url, name: "Soundtrack\(soundtracks.count + 1)Audio\(index + 1)_\(UUID().uuidString)") {
                if let tempPlayer = try? AVAudioPlayer(contentsOf: storedURL) {
                    let duration = tempPlayer.duration
                    let fileName = url.deletingPathExtension().lastPathComponent
                    if createReferenceLength == nil || abs(duration - createReferenceLength!) < 0.1 {
                        createAdditionalZStacks[index].audioURL = storedURL
                        createAdditionalZStacks[index].player = tempPlayer
                        createAdditionalZStacks[index].player?.volume = mapVolume(createAdditionalZStacks[index].volume)
                        createAdditionalZStacks[index].player?.prepareToPlay()
                        if createReferenceLength == nil {
                            createReferenceLength = duration
                        }
                        if index < createAdditionalTitles.count {
                            createAdditionalTitles[index] = fileName // Set dynamic title to file name
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

    private func pauseAllPreviewAudio() {
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

    private func getAllPlayingPreviewPlayers() -> [(player: AVAudioPlayer, isBase: Bool, index: Int?)] {
        var result: [(AVAudioPlayer, Bool, Int?)] = []
        if createBaseIsPlaying, let player = createBasePlayer {
            result.append((player, true, nil))
        }
        for (i, zstack) in createAdditionalZStacks.enumerated() {
            if zstack.isPlaying, let player = zstack.player {
                result.append((player, false, i))
            }
        }
        return result
    }

    private func syncAndPlayAllPreviews(syncTime: TimeInterval, exceptBase: Bool? = nil, exceptIndex: Int? = nil) {
        // Set all preview players' currentTime to syncTime and play
        if exceptBase != true, let player = createBasePlayer {
            player.currentTime = syncTime
            player.play()
            createBaseIsPlaying = true
        }
        for (i, zstack) in createAdditionalZStacks.enumerated() {
            if exceptIndex == nil || exceptIndex != i, let player = zstack.player {
                createAdditionalZStacks[i].player?.currentTime = syncTime
                createAdditionalZStacks[i].player?.play()
                createAdditionalZStacks[i].isPlaying = true
            }
        }
    }

    private func playAndSyncPreviews(startingIndex: Int?, isBase: Bool) {
        // Gather all preview tracks that were playing, plus the one just started
        var indicesToPlay: [Int] = []
        var shouldPlayBase = false
        var times: [TimeInterval] = []
        if isBase {
            shouldPlayBase = true
            if let basePlayer = createBasePlayer {
                times.append(basePlayer.currentTime)
            }
        } else if let idx = startingIndex {
            indicesToPlay.append(idx)
            if let player = createAdditionalZStacks[idx].player {
                times.append(player.currentTime)
            }
        }
        // Add all other preview tracks that were playing
        if createBaseIsPlaying && !isBase {
            shouldPlayBase = true
            if let basePlayer = createBasePlayer {
                times.append(basePlayer.currentTime)
            }
        }
        for (i, zstack) in createAdditionalZStacks.enumerated() {
            if zstack.isPlaying && (!isBase || i != startingIndex) {
                indicesToPlay.append(i)
                if let player = zstack.player {
                    times.append(player.currentTime)
                }
            }
        }
        // Pause all previews
        pauseAllPreviewAudio()
        // Find the farthest currentTime
        let maxTime = times.max() ?? 0
        // Set all to maxTime
        if shouldPlayBase, let basePlayer = createBasePlayer {
            basePlayer.currentTime = maxTime
        }
        for i in indicesToPlay {
            if let player = createAdditionalZStacks[i].player {
                player.currentTime = maxTime
            }
        }
        // Resume all
        if shouldPlayBase, let basePlayer = createBasePlayer {
            basePlayer.play()
            createBaseIsPlaying = true
        }
        for i in indicesToPlay {
            if let player = createAdditionalZStacks[i].player {
                player.play()
                createAdditionalZStacks[i].isPlaying = true
            }
        }
    }

    private func toggleBasePlayback() {
        guard let player = createBasePlayer else { return }
        // Pause main soundtrack if playing
        if audioController.isSoundtrackPlaying {
            audioController.toggleSoundtrackPlayback()
        }
        if createBaseIsPlaying {
            player.pause()
            createBaseIsPlaying = false
        } else {
            playAndSyncPreviews(startingIndex: nil, isBase: true)
        }
    }

    private func togglePlayback(at index: Int) {
        guard let player = createAdditionalZStacks[index].player else { return }
        // Pause main soundtrack if playing
        if audioController.isSoundtrackPlaying {
            audioController.toggleSoundtrackPlayback()
        }
        if createAdditionalZStacks[index].isPlaying {
            player.pause()
            createAdditionalZStacks[index].isPlaying = false
        } else {
            playAndSyncPreviews(startingIndex: index, isBase: false)
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

    // MARK: - Import System Logic
    private func handleImportZip(_ zipURL: URL) {
        print("handleImportZip called with: \(zipURL)")
        // Clean up any previous temp folder
        if let temp = importTempFolder {
            try? FileManager.default.removeItem(at: temp)
            importTempFolder = nil
        }
        let fileManager = FileManager.default
        do {
            // Create a temp folder
            let tempFolder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: tempFolder, withIntermediateDirectories: true)
            // Unzip
            try fileManager.unzipItem(at: zipURL, to: tempFolder)
            // Recursively find info.txt
            guard let infoURL = findInfoTxt(in: tempFolder) else {
                showImportPicker = false
                importError = "Import failed: info.txt not found in zip."
                print(importError ?? "")
                try? fileManager.removeItem(at: tempFolder)
                return
            }
            // Find all audio files recursively
            let audioFiles = findAudioFiles(in: tempFolder)
            if audioFiles.isEmpty {
                showImportPicker = false
                importError = "Import failed: No audio files found in zip."
                print(importError ?? "")
                try? fileManager.removeItem(at: tempFolder)
                return
            }
            // Parse info.txt
            let infoText = try String(contentsOf: infoURL)
            let (title, tracks) = parseInfoTxt(infoText: infoText, audioFiles: audioFiles)
            if tracks.isEmpty {
                showImportPicker = false
                importError = "Import failed: No valid tracks found in info.txt."
                print(importError ?? "")
                try? fileManager.removeItem(at: tempFolder)
                return
            }
            // Prepare AVAudioPlayers for preview
            var importTracksTemp: [ImportTrack] = []
            for t in tracks {
                if let fileURL = audioFiles.first(where: { $0.lastPathComponent == t.fileName }) {
                    let player = try? AVAudioPlayer(contentsOf: fileURL)
                    importTracksTemp.append(ImportTrack(displayName: t.displayName, fileURL: fileURL, minSpeed: t.minSpeed, maxSpeed: t.maxSpeed, volume: t.volume, player: player))
                } else {
                    showImportPicker = false
                    importError = "Import failed: Audio file \(t.fileName) referenced in info.txt not found in zip."
                    print(importError ?? "")
                    try? fileManager.removeItem(at: tempFolder)
                    return
                }
            }
            importSoundtrackTitle = title
            importTracks = importTracksTemp
            importTempFolder = tempFolder
            print("Parsed info.txt, navigating to import confirmation page")
            // showImportConfirmation = true
            showImportConfirmation = true
        } catch {
            showImportPicker = false
            importError = "Failed to import zip: \(error.localizedDescription)"
            print("Import error: \(error)")
        }
    }

    // Recursively find info.txt or soundtrack_info.txt
    private func findInfoTxt(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased() == "info.txt" || fileURL.lastPathComponent.lowercased() == "soundtrack_info.txt" {
                    return fileURL
                }
            }
        }
        return nil
    }

    // Recursively find all audio files
    private func findAudioFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        var audioFiles: [URL] = []
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if ext == "mp3" || ext == "wav" || ext == "m4a" {
                    audioFiles.append(fileURL)
                }
            }
        }
        return audioFiles
    }

    private func parseInfoTxt(infoText: String, audioFiles: [URL]) -> (String, [ParsedTrack]) {
        var title = ""
        var tracks: [ParsedTrack] = []
        let lines = infoText.components(separatedBy: .newlines)
        var currentTrack: ParsedTrack? = nil
        var currentName = ""
        var currentFile = ""
        var minSpeed = 0
        var maxSpeed = 0
        var volume: Float = 0.0
        for line in lines {
            if line.hasPrefix("Dynamidrive Soundtrack: ") {
                title = String(line.dropFirst("Dynamidrive Soundtrack: ".count))
            } else if line.hasPrefix("Track: ") {
                if !currentName.isEmpty && !currentFile.isEmpty {
                    tracks.append(ParsedTrack(displayName: currentName, fileName: currentFile, minSpeed: minSpeed, maxSpeed: maxSpeed, volume: volume))
                }
                currentName = String(line.dropFirst("Track: ".count))
                currentFile = ""
                minSpeed = 0
                maxSpeed = 0
                volume = 0.0
            } else if line.hasPrefix("File: ") {
                currentFile = String(line.dropFirst("File: ".count))
            } else if line == "Always playing" {
                minSpeed = 0
                maxSpeed = 0
            } else if line.hasPrefix("Speed range: ") {
                let range = line.replacingOccurrences(of: "Speed range: ", with: "").replacingOccurrences(of: " mph", with: "")
                let comps = range.components(separatedBy: "-")
                if comps.count == 2, let min = Int(comps[0].trimmingCharacters(in: .whitespaces)), let max = Int(comps[1].trimmingCharacters(in: .whitespaces)) {
                    minSpeed = min
                    maxSpeed = max
                }
            } else if line.hasPrefix("Volume: ") {
                let v = line.replacingOccurrences(of: "Volume: ", with: "")
                volume = Float(v.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
            }
        }
        if !currentName.isEmpty && !currentFile.isEmpty {
            tracks.append(ParsedTrack(displayName: currentName, fileName: currentFile, minSpeed: minSpeed, maxSpeed: maxSpeed, volume: volume))
        }
        return (title, tracks)
    }
} 
