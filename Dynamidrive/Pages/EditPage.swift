import SwiftUI
import AVFoundation

struct EditPage: View {
    @Binding var showEditPage: Bool
    @Binding var pendingSoundtrack: Soundtrack?
    @Binding var soundtracks: [Soundtrack]
    @EnvironmentObject private var audioController: AudioController
    @State private var showInfo2Page: Bool = false
    @State private var showColorPicker: Bool = false
    
    // State variables for editing
    @State private var editSoundtrackTitle: String = ""
    @State private var editBaseTitle: String = ""
    @State private var editAdditionalTitles: [String] = []
    @State private var editAdditionalAlwaysPlaying: [Bool] = []
    @State private var editAudio1MinimumSpeed: Int = 0
    @State private var editAudio1MaximumSpeed: Int = 80
    @State private var editAudio2MinimumSpeed: Int = 0
    @State private var editAudio2MaximumSpeed: Int = 80
    @State private var editAudio3MinimumSpeed: Int = 0
    @State private var editAudio3MaximumSpeed: Int = 80
    @State private var editAudio4MinimumSpeed: Int = 0
    @State private var editAudio4MaximumSpeed: Int = 80
    @State private var editAudio5MinimumSpeed: Int = 0
    @State private var editAudio5MaximumSpeed: Int = 80
    @State private var editSelectedCardColor: Color = .clear
    
    var saveSoundtracks: () -> Void
    
    var body: some View {
        PageLayout(
            title: "Edit",
            leftButtonAction: { showColorPicker = true },
            rightButtonAction: { showInfo2Page = true },
            leftButtonSymbol: "paintbrush",
            rightButtonSymbol: "info",
            bottomButtons: [
                PageButton(label: { Image(systemName: "arrow.uturn.backward").globalButtonStyle() }, action: {
                    showEditPage = false
                }),
                PageButton(label: { Image(systemName: "checkmark").globalButtonStyle() }, action: {
                    handleSaveAction()
                }),
                PageButton(label: { Image(systemName: "speaker.wave.3.fill").globalButtonStyle() }, action: {
                    // Volume page action - could be implemented later
                })
            ]
        ) {
            VStack() {
                editHeader()
                editTrackList()
                Spacer().frame(height: 100)
            }
        }
        .sheet(isPresented: $showInfo2Page) {
            info2Page()
        }
        .sheet(isPresented: $showColorPicker) {
            colorPickerSheet()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showColorPicker = false
                        }
                        .foregroundColor(.white)
                    }
                }
        }
        .onAppear {
            loadSoundtrackData()
        }
    }
    
    // MARK: - Load Soundtrack Data
    private func loadSoundtrackData() {
        guard let soundtrack = pendingSoundtrack else { return }
        
        editSoundtrackTitle = soundtrack.title
        editSelectedCardColor = soundtrack.cardColor
        
        // Load base track data
        if !soundtrack.tracks.isEmpty {
            editBaseTitle = soundtrack.tracks[0].displayName
        }
        
        // Load additional tracks data
        editAdditionalTitles.removeAll()
        editAdditionalAlwaysPlaying.removeAll()
        
        for (index, track) in soundtrack.tracks.enumerated() {
            if index > 0 { // Skip base track
                editAdditionalTitles.append(track.displayName)
                editAdditionalAlwaysPlaying.append(track.minimumSpeed == 0 && track.maximumSpeed == 0)
                
                // Set speed ranges based on track index
                switch index {
                case 1:
                    editAudio1MinimumSpeed = track.minimumSpeed
                    editAudio1MaximumSpeed = track.maximumSpeed
                case 2:
                    editAudio2MinimumSpeed = track.minimumSpeed
                    editAudio2MaximumSpeed = track.maximumSpeed
                case 3:
                    editAudio3MinimumSpeed = track.minimumSpeed
                    editAudio3MaximumSpeed = track.maximumSpeed
                case 4:
                    editAudio4MinimumSpeed = track.minimumSpeed
                    editAudio4MaximumSpeed = track.maximumSpeed
                case 5:
                    editAudio5MinimumSpeed = track.minimumSpeed
                    editAudio5MaximumSpeed = track.maximumSpeed
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Save Action
    private func handleSaveAction() {
        guard var soundtrack = pendingSoundtrack else { return }
        
        // Update soundtrack title
        soundtrack = Soundtrack(
            id: soundtrack.id,
            title: editSoundtrackTitle.trimmingCharacters(in: .whitespaces),
            tracks: createUpdatedTracks(),
            players: soundtrack.players,
            cardColor: editSelectedCardColor
        )
        
        // Update the pending soundtrack
        pendingSoundtrack = soundtrack
        
        // Update in the main soundtracks array if it exists there
        if let index = soundtracks.firstIndex(where: { $0.id == soundtrack.id }) {
            soundtracks[index] = soundtrack
        }
        
        // Update current soundtrack if it's the one being edited
        if audioController.currentSoundtrackTitle == soundtrack.title {
            audioController.setCurrentSoundtrack(
                id: soundtrack.id,
                tracks: soundtrack.tracks,
                players: soundtrack.players,
                title: soundtrack.title
            )
        }
        
        // Save changes
        saveSoundtracks()
        
        // Close the edit page
        showEditPage = false
    }
    
    // MARK: - Create Updated Tracks
    private func createUpdatedTracks() -> [AudioController.SoundtrackData] {
        guard let originalSoundtrack = pendingSoundtrack else { return [] }
        
        var updatedTracks: [AudioController.SoundtrackData] = []
        
        // Update base track
        if !originalSoundtrack.tracks.isEmpty {
            let baseTrack = originalSoundtrack.tracks[0]
            updatedTracks.append(AudioController.SoundtrackData(
                audioFileName: baseTrack.audioFileName,
                displayName: editBaseTitle,
                maximumVolume: baseTrack.maximumVolume,
                minimumSpeed: baseTrack.minimumSpeed,
                maximumSpeed: baseTrack.maximumSpeed
            ))
        }
        
        // Update additional tracks
        for (index, originalTrack) in originalSoundtrack.tracks.enumerated() {
            if index > 0 { // Skip base track
                let titleIndex = index - 1
                let displayName = titleIndex < editAdditionalTitles.count ? editAdditionalTitles[titleIndex] : originalTrack.displayName
                let alwaysPlaying = titleIndex < editAdditionalAlwaysPlaying.count ? editAdditionalAlwaysPlaying[titleIndex] : false
                
                var minSpeed = originalTrack.minimumSpeed
                var maxSpeed = originalTrack.maximumSpeed
                
                // Get speed values based on track index
                switch index {
                case 1:
                    minSpeed = alwaysPlaying ? 0 : editAudio1MinimumSpeed
                    maxSpeed = alwaysPlaying ? 0 : editAudio1MaximumSpeed
                case 2:
                    minSpeed = alwaysPlaying ? 0 : editAudio2MinimumSpeed
                    maxSpeed = alwaysPlaying ? 0 : editAudio2MaximumSpeed
                case 3:
                    minSpeed = alwaysPlaying ? 0 : editAudio3MinimumSpeed
                    maxSpeed = alwaysPlaying ? 0 : editAudio3MaximumSpeed
                case 4:
                    minSpeed = alwaysPlaying ? 0 : editAudio4MinimumSpeed
                    maxSpeed = alwaysPlaying ? 0 : editAudio4MaximumSpeed
                case 5:
                    minSpeed = alwaysPlaying ? 0 : editAudio5MinimumSpeed
                    maxSpeed = alwaysPlaying ? 0 : editAudio5MaximumSpeed
                default:
                    break
                }
                
                updatedTracks.append(AudioController.SoundtrackData(
                    audioFileName: originalTrack.audioFileName,
                    displayName: displayName,
                    maximumVolume: originalTrack.maximumVolume,
                    minimumSpeed: minSpeed,
                    maximumSpeed: maxSpeed
                ))
            }
        }
        
        return updatedTracks
    }
    
    // MARK: - Edit Page Helper Functions
    func additionalAudioZStack(geometry: GeometryProxy, index: Int) -> some View {
        var minSpeed: Binding<Int>
        var maxSpeed: Binding<Int>
        switch index {
        case 0:
            minSpeed = $editAudio1MinimumSpeed
            maxSpeed = $editAudio1MaximumSpeed
        case 1:
            minSpeed = $editAudio2MinimumSpeed
            maxSpeed = $editAudio2MaximumSpeed
        case 2:
            minSpeed = $editAudio3MinimumSpeed
            maxSpeed = $editAudio3MaximumSpeed
        case 3:
            minSpeed = $editAudio4MinimumSpeed
            maxSpeed = $editAudio4MaximumSpeed
        case 4:
            minSpeed = $editAudio5MinimumSpeed
            maxSpeed = $editAudio5MaximumSpeed
        default:
            minSpeed = .constant(0)
            maxSpeed = .constant(80)
        }
        
        let alwaysPlaying = Binding(
            get: { index < editAdditionalAlwaysPlaying.count ? editAdditionalAlwaysPlaying[index] : false },
            set: { newValue in
                while index >= editAdditionalAlwaysPlaying.count {
                    editAdditionalAlwaysPlaying.append(false)
                }
                editAdditionalAlwaysPlaying[index] = newValue
                if newValue {
                    minSpeed.wrappedValue = 0
                    maxSpeed.wrappedValue = 0
                }
            }
        )
        
        return ZStack {
            GlobalCardAppearance
            VStack(spacing: 2) {
                TextField("Audio \(index + 1)", text: Binding(
                    get: { index < editAdditionalTitles.count ? editAdditionalTitles[index] : "Audio \(index + 1)" },
                    set: { newValue in
                        while index >= editAdditionalTitles.count {
                            editAdditionalTitles.append("Audio \(editAdditionalTitles.count + 1)")
                            editAdditionalAlwaysPlaying.append(false)
                        }
                        editAdditionalTitles[index] = newValue
                    }
                ))
                .font(.system(size: 35, weight: .semibold))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                .minimumScaleFactor(0.3)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .offset(x:-35)
                .foregroundColor(.white)
                .padding(.top, 16)
                .submitLabel(.done)
                HStack(spacing: 10) {
                    Picker("Min", selection: minSpeed) {
                        ForEach(0...maxSpeed.wrappedValue, id: \.self) { speed in
                            Text("\(speed)")
                                .foregroundColor(.white)
                                .tag(speed)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    .opacity(alwaysPlaying.wrappedValue ? 0.25 : 1.0)
                    Text("-")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.white)
                        .opacity(alwaysPlaying.wrappedValue ? 0.25 : 1.0)
                    Picker("Max", selection: maxSpeed) {
                        ForEach(minSpeed.wrappedValue...80, id: \.self) { speed in
                            Text("\(speed)")
                                .foregroundColor(.white)
                                .tag(speed)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    .opacity(alwaysPlaying.wrappedValue ? 0.25 : 1.0)
                    Text("mph")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(0.25)
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, -4)
            }
            Button(action: {
                alwaysPlaying.wrappedValue.toggle()
            }) {
                Image(systemName: "infinity")
                    .font(.system(size: 16))
                    .foregroundColor(alwaysPlaying.wrappedValue ? Color(red: 0.5, green: 0.5, blue: 0.5) : .white)
                    .frame(width: 30, height: 30)
                    .background(alwaysPlaying.wrappedValue ? Color.white : Color.white.opacity(0.0))
                    .clipShape(Circle())
                 .glassEffect(.regular.tint(.clear).interactive())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 15)
            .padding(.bottom, 10)
            .offset(y: -12)
        }
        .animation(.easeInOut(duration: 0.3), value: alwaysPlaying.wrappedValue)
        .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
    }
    
    @ViewBuilder
    private func editHeader() -> some View {
        ZStack {
            GlobalCardAppearance
            TextField("Soundtrack Title", text: $editSoundtrackTitle)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: 50)
        }
        .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
    }
    
    @ViewBuilder
    private func editTrackList() -> some View {
        VStack(spacing: 10) {
            if let soundtrack = pendingSoundtrack, !soundtrack.tracks.isEmpty {
                GeometryReader { geometry in
                    ZStack {
                        GlobalCardAppearance
                        VStack(spacing: 0) {
                            TextField("Base", text: $editBaseTitle)
                                .font(.system(size: 35, weight: .semibold))
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                .minimumScaleFactor(0.3)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .offset(x:-47)
                                .foregroundColor(.white)
                                .padding(.leading, 16)
                                .padding(.top, -8)
                                .submitLabel(.done)
                            Text("Tap to rename")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .opacity(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 16)
                                .offset(x: 7)
                        }
                    }
                }
                .frame(height: 108)
                .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
            }
            
            // Additional tracks
            if let soundtrack = pendingSoundtrack {
                ForEach(Array(soundtrack.tracks.enumerated()), id: \.offset) { index, track in
                    if index > 0 { // Skip base track
                        GeometryReader { geometry in
                            additionalAudioZStack(geometry: geometry, index: index - 1)
                        }
                        .frame(height: 160)
                    }
                }
            }
        }
    }

    // MARK: Info2 Page
    private func info2Page() -> some View {
        Color(red: 26/255, green: 20/255, blue: 26/255)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                VStack(alignment: .leading, spacing: 20) {
                    Text("Edit Page Info")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundColor(.white)
                    Text("Edit your soundtrack settings here. You can change track names, speed ranges, and card colors.")
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
            )
    }

    // MARK: Color Picker Sheet
    private func colorPickerSheet() -> some View {
        VStack(spacing: 30) {
            // Custom title at top
            Text("Choose a Color")
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 40)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 15) {
                ForEach(systemColors, id: \.self) { color in
                    Button(action: {
                        editSelectedCardColor = color
                    }) {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(color == .clear ? Color.gray.opacity(0.1) : color)
                            .frame(height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white, lineWidth: editSelectedCardColor == color ? 3 : 0)
                            )
                    }
                }
            }
            
            // Explanatory text
            Text("All cards have a Liquid Glass material. Clear cards will reflect the color of the card above it.")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Preview card
            VStack(spacing: 0) {
                Text("Preview")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.bottom, 20)
                
                ZStack {
                    Rectangle()
                        .fill(.clear)
                        .cornerRadius(20)
                        .glassEffect(.regular.tint(editSelectedCardColor == .clear ? .clear : editSelectedCardColor).interactive(), in: .rect(cornerRadius: 20.0))
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(editSoundtrackTitle.isEmpty ? "Soundtrack Title" : editSoundtrackTitle)
                                    .foregroundColor(.white)
                                    .font(.system(size: 28, weight: .semibold))
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                    .minimumScaleFactor(0.3)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(1)
                                
                                Text("Distance Played: 0 mi")
                                    .foregroundColor(editSelectedCardColor == .clear ? .gray : .white)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        
                        // Fake play button
                        if editSelectedCardColor == .clear {
                            Image(systemName: "play.fill")
                                .globalButtonStyle()
                        } else {
                            Image(systemName: "play.fill")
                                .CardButtonStyle()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 108)
            }
            
            Spacer()
        }
        .padding(.horizontal)
    }
    
    // System colors excluding grays and white
    private let systemColors: [Color] = [
        .clear,
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .cyan,
        .blue,
        .indigo,
        .purple,
        .pink,
        .brown
    ]
} 