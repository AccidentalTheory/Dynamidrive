import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct AIUploadPage: View {
    let onBack: () -> Void
    @Binding var showConfigurePage: Bool
    @Binding var createBaseAudioURL: URL?
    @Binding var createAdditionalZStacks: [ZStackData]
    @Binding var createAdditionalTitles: [String]
    @Binding var createReferenceLength: TimeInterval?
    @Binding var createNextID: Int
    @Binding var currentPage: AppPage
    @Binding var showUploading: Bool
    @Binding var isUploading: Bool
    
    @State private var showFileImporter = false
    @State private var selectedFileURL: URL?
    @State private var showBaseTrackSheet = false
    @State private var downloadedTrackURLs: [URL] = []
    @State private var selectedBaseIndex: Int = 0

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
                    PageButton(label: { Image(systemName: "chevron.left").globalButtonStyle() }, action: onBack),
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showUploading = true
                        isUploading = true
                        currentPage = .uploading
                    }
                    AIHandler.uploadAudio(url: url) { result in
                        switch result {
                        case .success(let baseName):
                            isUploading = false
                            pollForTracks(baseName: baseName)
                        case .failure(_):
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showUploading = false
                                isUploading = false
                                currentPage = .aiUpload
                            }
                        }
                    }
                }
            case .failure(_):
                break
            }
        }
        .sheet(isPresented: $showBaseTrackSheet) {
            BaseTrackSelectionSheet(
                trackNames: ["Drums", "Bass", "Voice", "Other"],
                onSelect: { index in
                    selectedBaseIndex = index
                    // Set the base audio URL and additional tracks for configure page
                    createBaseAudioURL = downloadedTrackURLs[index]
                    createAdditionalZStacks = []
                    createAdditionalTitles = []
                    // Add the other tracks (in order, skipping the selected base)
                    for i in 0..<downloadedTrackURLs.count {
                        if i != index {
                            var zStackData = ZStackData(id: createAdditionalZStacks.count + 1)
                            zStackData.audioURL = downloadedTrackURLs[i]
                            zStackData.volume = 1.0
                            createAdditionalZStacks.append(zStackData)
                            // Map index to title
                            let titles = ["Drums", "Bass", "Voice", "Other"]
                            createAdditionalTitles.append(titles[i])
                        }
                    }
                    // Get reference length from selected base track
                    let baseURL = downloadedTrackURLs[index]
                    do {
                        let basePlayer = try AVAudioPlayer(contentsOf: baseURL)
                        createReferenceLength = basePlayer.duration
                    } catch {
                        createReferenceLength = 0
                    }
                    createNextID = createAdditionalZStacks.count + 1
                    // Only now, after selection, navigate to configure page
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showConfigurePage = true
                        currentPage = .configure
                    }
                    showBaseTrackSheet = false
                },
                selectedIndex: $selectedBaseIndex
            )
        }
    }
    
    private func pollForTracks(baseName: String) {
        AIHandler.pollForTracks(baseName: baseName) { tracks in
            if let tracks = tracks {
                // Download tracks
                AIHandler.downloadTracks(tracks: tracks) { downloadedURLs in
                    if let downloadedURLs = downloadedURLs {
                        // Hide uploading screen first, then show base track selection sheet
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showUploading = false
                            isUploading = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            downloadedTrackURLs = downloadedURLs
                            selectedBaseIndex = 0
                            showBaseTrackSheet = true
                        }
                    } else {
                        // Handle download error - go back to AI upload page
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showUploading = false
                            isUploading = false
                            currentPage = .aiUpload
                        }
                    }
                }
            } else {
                // Continue polling
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    pollForTracks(baseName: baseName)
                }
            }
        }
    }
} 

// MARK: - BaseTrackSelectionSheet
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
