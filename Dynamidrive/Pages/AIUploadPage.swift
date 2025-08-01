import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct AIUploadPage: View {
    let onBack: () -> Void
    @Binding var showCreatePage: Bool
    @Binding var showConfigurePage: Bool
    @Binding var createBaseAudioURL: URL?
    @Binding var createBasePlayer: AVAudioPlayer?
    @Binding var createBaseIsPlaying: Bool
    @Binding var createBaseOffset: CGFloat
    @Binding var createBaseShowingFilePicker: Bool
    @Binding var createBaseVolume: Float
    @Binding var createAdditionalZStacks: [ZStackData]
    @Binding var createAdditionalTitles: [String]
    @Binding var createAdditionalAlwaysPlaying: [Bool]
    @Binding var createBaseTitle: String
    @Binding var createSoundtrackTitle: String
    @Binding var createReferenceLength: TimeInterval?
    @Binding var createNextID: Int
    @Binding var currentPage: AppPage
    @Binding var showUploading: Bool
    @Binding var isUploading: Bool
    @Binding var isDownloading: Bool
    @Binding var soundtracks: [Soundtrack]
    @Binding var createAudio1MinimumSpeed: Int
    @Binding var createAudio1MaximumSpeed: Int
    @Binding var createAudio2MinimumSpeed: Int
    @Binding var createAudio2MaximumSpeed: Int
    @Binding var createAudio3MinimumSpeed: Int
    @Binding var createAudio3MaximumSpeed: Int
    @Binding var createAudio4MinimumSpeed: Int
    @Binding var createAudio4MaximumSpeed: Int
    @Binding var createAudio5MinimumSpeed: Int
    @Binding var createAudio5MaximumSpeed: Int
    
    @State private var showFileImporter = false
    @State private var selectedFileURL: URL?
    @State private var downloadedTrackURLs: [URL] = []
    @State private var downloadedTrackTypes: [String] = []
    @State private var pollingTimer: Timer?
    @State private var currentBaseName: String?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var filesDownloaded: Bool = false
    @State private var pollingStartTime: Date?
    @State private var discoveredTracks: [SeparatedTrack] = []
    private let maxPollingDuration: TimeInterval = 600 // 10 minutes max

    var body: some View {
        ZStack {
            MeshGradientView()
                .ignoresSafeArea(.all, edges: .all)
            
            // Main content using PageLayout
            PageLayout(
                title: "",
                leftButtonAction: {},
                rightButtonAction: {},
                leftButtonSymbol: "",
                rightButtonSymbol: "",
                bottomButtons: [
                    PageButton(label: { Image(systemName: "arrow.uturn.backward").globalButtonStyle() }, action: onBack),
                    PageButton(label: { Image(systemName: "arrow.up.circle.dotted").globalButtonStyle() }, action: {
                        showFileImporter = true
                    })
                ],
                showEdgeGradients: true
            ) {
                VStack(spacing: 40) {
                    // Icon
                    Image(systemName: "sparkles")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                        
                    
                    // Title and description
                    VStack(spacing: 16) {
                        Text("AI Audio Separation")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Upload your audio file and let AI separate it into individual tracks: drums, bass, vocals, and other instruments.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // File type info
                    VStack(spacing: 8) {
                        Text("Supported formats:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("MP3, WAV")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))

                            Text("Limit: 100MB")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Error message if any
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Success message if any
                    if let successMessage = successMessage {
                        Text(successMessage)
                            .foregroundColor(.green)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        

                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.mp3, UTType.wav],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                    errorMessage = nil // Clear any previous errors
                    successMessage = nil // Clear any previous success messages
                    filesDownloaded = false // Clear download status
                    print("[AIUploadPage] File selected: \(url.lastPathComponent)")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showUploading = true
                        isUploading = true
                        currentPage = .uploading
                    }
                    AIHandler.uploadAudio(url: url) { result in
                        switch result {
                        case .success(let baseName):
                            currentBaseName = baseName
                            isUploading = false
                            print("[AIUploadPage] Upload successful, starting polling for baseName: \(baseName)")
                            startPollingForTracks(baseName: baseName)
                        case .failure(let error):
                            print("[AIUploadPage] Upload failed: \(error.localizedDescription)")
                            errorMessage = "Upload failed: \(error.localizedDescription)"
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showUploading = false
                                isUploading = false
                                currentPage = .aiUpload
                            }
                        }
                    }
                }
            case .failure(let error):
                print("[AIUploadPage] File selection failed: \(error.localizedDescription)")
                errorMessage = "File selection failed: \(error.localizedDescription)"
                break
            }
        }
        .onDisappear {
            print("[AIUploadPage] Page disappearing, stopping polling timer")
            stopPollingTimer()
        }
        .onChange(of: currentPage) { oldPage, newPage in
            if newPage != .aiUpload && newPage != .uploading {
                print("[AIUploadPage] Page changed from \(oldPage) to \(newPage), stopping polling timer")
                stopPollingTimer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiDownloadCompleted)) { notification in
            print("[AIUploadPage] Received aiDownloadCompleted notification")
            DispatchQueue.main.async {
                if let downloadedTracks = notification.object as? [SeparatedTrack] {
                    print("[AIUploadPage] Download completed, setting up CreatePage with downloaded tracks")
                    print("[AIUploadPage] Current state before completion: showUploading=\(showUploading), isDownloading=\(isDownloading), currentPage=\(currentPage)")
                    
                    // Track setup is now handled by ContentView
                    print("[AIUploadPage] Download completed, track setup will be handled by ContentView")
                    
                    // Reset downloading state and navigate to AI configure page instead of create page
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDownloading = false
                        isUploading = false
                        showUploading = false
                    }
                    
                    // Small delay to ensure uploading screen is hidden before navigation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        print("[AIUploadPage] Navigating to aiConfigure page")
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentPage = .aiConfigure // Navigate directly to AI Configure page
                        }
                    }
                    
                    print("[AIUploadPage] State after completion: showUploading=\(showUploading), isDownloading=\(isDownloading), currentPage=\(currentPage)")
                }
            }
        }
    }
    
    private func startPollingForTracks(baseName: String) {
        print("[AIUploadPage] Starting polling for tracks with baseName: \(baseName)")
        stopPollingTimer()
        pollingStartTime = Date()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            fetchSeparatedTracks(baseName: baseName)
        }
    }
    
    private func fetchSeparatedTracks(baseName: String) {
        print("[AIUploadPage] Fetching separated tracks for baseName: \(baseName)")
        
        // Check for timeout
        if let startTime = pollingStartTime, Date().timeIntervalSince(startTime) > maxPollingDuration {
            print("[AIUploadPage] Polling timeout reached (5 minutes), stopping polling")
            stopPollingTimer()
            errorMessage = "AI separation timed out. Please try again."
            withAnimation(.easeInOut(duration: 0.2)) {
                showUploading = false
                isUploading = false
                currentPage = .aiUpload
            }
            return
        }
        
        AIHandler.pollForTracks(baseName: baseName) { tracks in
            if let tracks = tracks {
                print("[AIUploadPage] All tracks discovered on website! Stopping polling immediately.")
                stopPollingTimer() // Stop polling immediately when tracks are discovered
                
                // Show downloading message and stay on upload page
                self.successMessage = "AI separation completed! Downloading tracks..."
                self.filesDownloaded = true
                
                // Keep user on upload page while downloading - don't set showUploading again
                withAnimation(.easeInOut(duration: 0.2)) {
                    isUploading = false
                    isDownloading = true // This will show "Downloading..." instead of "Processing..."
                    // Don't navigate yet - wait for download to complete
                }
                
                // Handle the separated tracks (download will happen in background)
                handleSeparatedTracks(tracks: tracks)
            } else {
                print("[AIUploadPage] Not all tracks ready yet, continuing to poll...")
                // Continue polling - timer will call this again
            }
        }
    }
    
    private func handleSeparatedTracks(tracks: [SeparatedTrack]) {
        print("[AIUploadPage] Handling \(tracks.count) discovered tracks...")
        
        // Organize tracks by type (these are the discovered tracks, not downloaded yet)
        let drumsTrack = tracks.first { $0.trackType == "Drums" }
        let bassTrack = tracks.first { $0.trackType == "Bass" }
        let voiceTrack = tracks.first { $0.trackType == "Vocals" }
        let otherTrack = tracks.first { $0.trackType == "Other" }
        
        print("[AIUploadPage] Organized discovered tracks - Drums: \(drumsTrack?.name ?? "nil"), Bass: \(bassTrack?.name ?? "nil"), Vocals: \(voiceTrack?.name ?? "nil"), Other: \(otherTrack?.name ?? "nil")")
        
        // Store the discovered tracks for later use when download completes
        discoveredTracks = tracks
        print("[AIUploadPage] Storing discovered tracks for later setup")
    }
    

    
    private func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    

    

} 

// MARK: - BaseTrackSelectionSheet (keeping for potential future use)
struct BaseTrackSelectionSheet: View {
    let trackNames: [String]
    let onSelect: (Int) -> Void
    @Binding var selectedIndex: Int

    var body: some View {
        VStack(spacing: 24) {
            Text("Select a Base track")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 24)
            ForEach(trackNames.indices, id: \.self) { i in
                Button(action: {
                    selectedIndex = i
                }) {
                    HStack {
                        Text(trackNames[i])
                            .font(.headline)
                            .foregroundColor(selectedIndex == i ? .white : .primary)
                        Spacer()
                        if selectedIndex == i {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(selectedIndex == i ? Color.blue.opacity(0.7) : Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            Spacer()
            Button(action: {
                onSelect(selectedIndex)
            }) {
                Text("Select")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity)
    }
} 
