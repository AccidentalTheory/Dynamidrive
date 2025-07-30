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
    
    // Track audio file assignments for swapping
    @State private var audioFileAssignments: [String] = []
    @State private var trackPositions: [Int] = [] // Maps UI position to original track index
    
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
        
        // Initialize audio file assignments
        audioFileAssignments = soundtrack.tracks.map { $0.audioFileName }
        // Initialize track positions (each track starts in its original position)
        trackPositions = Array(0..<soundtrack.tracks.count)
        
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
        
        // Create updated tracks
        let updatedTracks = createUpdatedTracks()
        
        // Reorder players to match the new audio file assignments
        var reorderedPlayers: [AVAudioPlayer?] = []
        for (newIndex, audioFile) in audioFileAssignments.enumerated() {
            // Find the original track that had this audio file
            if let originalTrackIndex = soundtrack.tracks.firstIndex(where: { $0.audioFileName == audioFile }) {
                // Get the player that was at the original track index
                let player = originalTrackIndex < soundtrack.players.count ? soundtrack.players[originalTrackIndex] : nil
                reorderedPlayers.append(player)
            } else {
                reorderedPlayers.append(nil)
            }
        }
        
        // Update soundtrack title
        soundtrack = Soundtrack(
            id: soundtrack.id,
            title: editSoundtrackTitle.trimmingCharacters(in: .whitespaces),
            tracks: updatedTracks,
            players: reorderedPlayers,
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
            // Force volume recalculation for the new track assignments
            audioController.adjustVolumesForSpeed(audioController.locationHandler.speedMPH)
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
        
        // Update base track using swapped audio file
        if !audioFileAssignments.isEmpty {
            let baseAudioFile = audioFileAssignments[0]
            let baseTrack = originalSoundtrack.tracks.first { $0.audioFileName == baseAudioFile } ?? originalSoundtrack.tracks[0]
            updatedTracks.append(AudioController.SoundtrackData(
                audioFileName: baseAudioFile,
                displayName: editBaseTitle,
                maximumVolume: baseTrack.maximumVolume,
                minimumSpeed: 0, // Base track always plays
                maximumSpeed: 0   // Base track always plays
            ))
        }
        
        // Update additional tracks using swapped audio files
        for (index, originalTrack) in originalSoundtrack.tracks.enumerated() {
            if index > 0 { // Skip base track
                let titleIndex = index - 1
                let displayName = titleIndex < editAdditionalTitles.count ? editAdditionalTitles[titleIndex] : originalTrack.displayName
                let alwaysPlaying = titleIndex < editAdditionalAlwaysPlaying.count ? editAdditionalAlwaysPlaying[titleIndex] : false
                
                // Get the swapped audio file for this position
                let audioFile = index < audioFileAssignments.count ? audioFileAssignments[index] : originalTrack.audioFileName
                let trackForVolume = originalSoundtrack.tracks.first { $0.audioFileName == audioFile } ?? originalTrack
                
                // Get the original track position for this UI position to determine speed values
                let originalTrackIndex = index < trackPositions.count ? trackPositions[index] : index
                
                var minSpeed = originalTrack.minimumSpeed
                var maxSpeed = originalTrack.maximumSpeed
                
                // Get speed values based on original track position
                switch originalTrackIndex {
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
                    audioFileName: audioFile,
                    displayName: displayName,
                    maximumVolume: trackForVolume.maximumVolume,
                    minimumSpeed: minSpeed,
                    maximumSpeed: maxSpeed
                ))
            }
        }
        
        return updatedTracks
    }
    
    // MARK: - Track Reordering
    private func moveTrack(at source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < editAdditionalTitles.count,
              destination >= 0, destination < editAdditionalTitles.count else { return }
        // Move Titles
        let title = editAdditionalTitles.remove(at: source)
        editAdditionalTitles.insert(title, at: destination);
        // Move AlwaysPlaying
        if source < editAdditionalAlwaysPlaying.count {
            let always = editAdditionalAlwaysPlaying.remove(at: source)
            editAdditionalAlwaysPlaying.insert(always, at: destination)
        }
        // Move speed values if needed (optional, for 5-track limit)
        let minSpeeds = [
            $editAudio1MinimumSpeed, $editAudio2MinimumSpeed, $editAudio3MinimumSpeed, $editAudio4MinimumSpeed, $editAudio5MinimumSpeed
        ]
        let maxSpeeds = [
            $editAudio1MaximumSpeed, $editAudio2MaximumSpeed, $editAudio3MaximumSpeed, $editAudio4MaximumSpeed, $editAudio5MaximumSpeed
        ]
        if source < minSpeeds.count && destination < minSpeeds.count {
            let minVal = minSpeeds[source].wrappedValue
            let maxVal = maxSpeeds[source].wrappedValue
            minSpeeds[source].wrappedValue = minSpeeds[destination].wrappedValue
            maxSpeeds[source].wrappedValue = maxSpeeds[destination].wrappedValue
            minSpeeds[destination].wrappedValue = minVal
            maxSpeeds[destination].wrappedValue = maxVal
        }
    }
    
    // MARK: - Edit Page Helper Functions
    func additionalAudioZStack(geometry: GeometryProxy, index: Int) -> some View {
        // Get the original track position for this UI position
        let originalTrackIndex = index < trackPositions.count ? trackPositions[index + 1] : index + 1
        
        var minSpeed: Binding<Int>
        var maxSpeed: Binding<Int>
        switch originalTrackIndex {
        case 1:
            minSpeed = $editAudio1MinimumSpeed
            maxSpeed = $editAudio1MaximumSpeed
        case 2:
            minSpeed = $editAudio2MinimumSpeed
            maxSpeed = $editAudio2MaximumSpeed
        case 3:
            minSpeed = $editAudio3MinimumSpeed
            maxSpeed = $editAudio3MaximumSpeed
        case 4:
            minSpeed = $editAudio4MinimumSpeed
            maxSpeed = $editAudio4MaximumSpeed
        case 5:
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
        
        return ZStack(alignment: .topTrailing) {
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
                // Remove Move Up/Down Buttons
            }
            // Order Button Menu (top right, glass style, 30x30, .padding(.top, 18))
            HStack {
                Spacer()
                Menu {
                    // This is a dynamic track, so it can swap with base or other dynamic tracks
                    Button(action: { swapBaseWithDynamic(index) }) {
                        HStack {
                            Text("Base")
                            Spacer()
                        }
                    }
                    ForEach(0..<editAdditionalTitles.count, id: \.self) { i in
                        Button(action: { 
                            if i == index {
                                // Same track, do nothing
                            } else {
                                swapDynamicWithDynamic(index, i)
                            }
                        }) {
                            HStack {
                                Text("Track \(i + 1)")
                                if i == index {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(index + 1)")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.0))
                        .clipShape(Circle())
                        .glassEffect(.regular.tint(.clear).interactive())
                }
                .padding(.trailing, 15)
                .padding(.top, 18)
            }
            // Infinity button (bottom right)
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
                    ZStack(alignment: .center) {
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
                        // Order Button Menu (vertically centered, right, glass style)
                        HStack {
                            Spacer()
                            Menu {
                                // This is the base track, so it can swap with any dynamic track
                                Button(action: { /* Already base, do nothing */ }) {
                                    HStack {
                                        Text("Base")
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                                ForEach(0..<editAdditionalTitles.count, id: \.self) { i in
                                    Button(action: { swapBaseWithDynamic(i) }) {
                                        HStack {
                                            Text("Track \(i + 1)")
                                        }
                                    }
                                }
                            } label: {
                                Text("B")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.0))
                                    .clipShape(Circle())
                                    .glassEffect(.regular.tint(.clear).interactive())
                            }
                            .padding(.trailing, 15)
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

    // Add swapBaseWithDynamic logic for EditPage
    private func swapBaseWithDynamic(_ dynamicIdx: Int) {
        // Save base track info
        let oldBaseTitle = editBaseTitle
        
        // Save dynamic track info
        let dynamicTitle = editAdditionalTitles[dynamicIdx]
        let dynamicMinSpeed: Int
        let dynamicMaxSpeed: Int
        
        // Get the speed values for the dynamic track based on its index
        switch dynamicIdx {
        case 0:
            dynamicMinSpeed = editAudio1MinimumSpeed
            dynamicMaxSpeed = editAudio1MaximumSpeed
        case 1:
            dynamicMinSpeed = editAudio2MinimumSpeed
            dynamicMaxSpeed = editAudio2MaximumSpeed
        case 2:
            dynamicMinSpeed = editAudio3MinimumSpeed
            dynamicMaxSpeed = editAudio3MaximumSpeed
        case 3:
            dynamicMinSpeed = editAudio4MinimumSpeed
            dynamicMaxSpeed = editAudio4MaximumSpeed
        case 4:
            dynamicMinSpeed = editAudio5MinimumSpeed
            dynamicMaxSpeed = editAudio5MaximumSpeed
        default:
            dynamicMinSpeed = 0
            dynamicMaxSpeed = 80
        }
        
        // Swap titles
        editBaseTitle = dynamicTitle
        editAdditionalTitles[dynamicIdx] = oldBaseTitle
        
        // Swap audio files
        if !audioFileAssignments.isEmpty && dynamicIdx + 1 < audioFileAssignments.count {
            let baseAudioFile = audioFileAssignments[0]
            let dynamicAudioFile = audioFileAssignments[dynamicIdx + 1]
            audioFileAssignments[0] = dynamicAudioFile
            audioFileAssignments[dynamicIdx + 1] = baseAudioFile
        }
        
        // Swap track positions
        if !trackPositions.isEmpty && dynamicIdx + 1 < trackPositions.count {
            let basePosition = trackPositions[0]
            let dynamicPosition = trackPositions[dynamicIdx + 1]
            trackPositions[0] = dynamicPosition
            trackPositions[dynamicIdx + 1] = basePosition
        }
        
        // Set the new dynamic track (old base) to have the speed values of the old dynamic track
        switch dynamicIdx {
        case 0:
            editAudio1MinimumSpeed = dynamicMinSpeed
            editAudio1MaximumSpeed = dynamicMaxSpeed
        case 1:
            editAudio2MinimumSpeed = dynamicMinSpeed
            editAudio2MaximumSpeed = dynamicMaxSpeed
        case 2:
            editAudio3MinimumSpeed = dynamicMinSpeed
            editAudio3MaximumSpeed = dynamicMaxSpeed
        case 3:
            editAudio4MinimumSpeed = dynamicMinSpeed
            editAudio4MaximumSpeed = dynamicMaxSpeed
        case 4:
            editAudio5MinimumSpeed = dynamicMinSpeed
            editAudio5MaximumSpeed = dynamicMaxSpeed
        default:
            break
        }
        
        // Set the new dynamic track to not always play (since it's now a dynamic track)
        if dynamicIdx < editAdditionalAlwaysPlaying.count {
            editAdditionalAlwaysPlaying[dynamicIdx] = false
        }
    }
    
    // Add swapDynamicWithDynamic logic for EditPage
    private func swapDynamicWithDynamic(_ fromIdx: Int, _ toIdx: Int) {
        // Save track info
        let fromTitle = editAdditionalTitles[fromIdx]
        let toTitle = editAdditionalTitles[toIdx]
        
        // Get the speed values for both tracks
        let fromMinSpeed: Int
        let fromMaxSpeed: Int
        let toMinSpeed: Int
        let toMaxSpeed: Int
        
        switch fromIdx {
        case 0:
            fromMinSpeed = editAudio1MinimumSpeed
            fromMaxSpeed = editAudio1MaximumSpeed
        case 1:
            fromMinSpeed = editAudio2MinimumSpeed
            fromMaxSpeed = editAudio2MaximumSpeed
        case 2:
            fromMinSpeed = editAudio3MinimumSpeed
            fromMaxSpeed = editAudio3MaximumSpeed
        case 3:
            fromMinSpeed = editAudio4MinimumSpeed
            fromMaxSpeed = editAudio4MaximumSpeed
        case 4:
            fromMinSpeed = editAudio5MinimumSpeed
            fromMaxSpeed = editAudio5MaximumSpeed
        default:
            fromMinSpeed = 0
            fromMaxSpeed = 80
        }
        
        switch toIdx {
        case 0:
            toMinSpeed = editAudio1MinimumSpeed
            toMaxSpeed = editAudio1MaximumSpeed
        case 1:
            toMinSpeed = editAudio2MinimumSpeed
            toMaxSpeed = editAudio2MaximumSpeed
        case 2:
            toMinSpeed = editAudio3MinimumSpeed
            toMaxSpeed = editAudio3MaximumSpeed
        case 3:
            toMinSpeed = editAudio4MinimumSpeed
            toMaxSpeed = editAudio4MaximumSpeed
        case 4:
            toMinSpeed = editAudio5MinimumSpeed
            toMaxSpeed = editAudio5MaximumSpeed
        default:
            toMinSpeed = 0
            toMaxSpeed = 80
        }
        
        // Swap titles
        editAdditionalTitles[fromIdx] = toTitle
        editAdditionalTitles[toIdx] = fromTitle
        
        // Swap audio files
        if !audioFileAssignments.isEmpty && fromIdx + 1 < audioFileAssignments.count && toIdx + 1 < audioFileAssignments.count {
            let fromAudioFile = audioFileAssignments[fromIdx + 1]
            let toAudioFile = audioFileAssignments[toIdx + 1]
            audioFileAssignments[fromIdx + 1] = toAudioFile
            audioFileAssignments[toIdx + 1] = fromAudioFile
        }
        
        // Swap track positions
        if !trackPositions.isEmpty && fromIdx + 1 < trackPositions.count && toIdx + 1 < trackPositions.count {
            let fromPosition = trackPositions[fromIdx + 1]
            let toPosition = trackPositions[toIdx + 1]
            trackPositions[fromIdx + 1] = toPosition
            trackPositions[toIdx + 1] = fromPosition
        }
        
        // Swap speed values
        switch fromIdx {
        case 0:
            editAudio1MinimumSpeed = toMinSpeed
            editAudio1MaximumSpeed = toMaxSpeed
        case 1:
            editAudio2MinimumSpeed = toMinSpeed
            editAudio2MaximumSpeed = toMaxSpeed
        case 2:
            editAudio3MinimumSpeed = toMinSpeed
            editAudio3MaximumSpeed = toMaxSpeed
        case 3:
            editAudio4MinimumSpeed = toMinSpeed
            editAudio4MaximumSpeed = toMaxSpeed
        case 4:
            editAudio5MinimumSpeed = toMinSpeed
            editAudio5MaximumSpeed = toMaxSpeed
        default:
            break
        }
        
        switch toIdx {
        case 0:
            editAudio1MinimumSpeed = fromMinSpeed
            editAudio1MaximumSpeed = fromMaxSpeed
        case 1:
            editAudio2MinimumSpeed = fromMinSpeed
            editAudio2MaximumSpeed = fromMaxSpeed
        case 2:
            editAudio3MinimumSpeed = fromMinSpeed
            editAudio3MaximumSpeed = fromMaxSpeed
        case 3:
            editAudio4MinimumSpeed = fromMinSpeed
            editAudio4MaximumSpeed = fromMaxSpeed
        case 4:
            editAudio5MinimumSpeed = fromMinSpeed
            editAudio5MaximumSpeed = fromMaxSpeed
        default:
            break
        }
        
        // Swap always playing states
        if fromIdx < editAdditionalAlwaysPlaying.count && toIdx < editAdditionalAlwaysPlaying.count {
            let fromAlwaysPlaying = editAdditionalAlwaysPlaying[fromIdx]
            let toAlwaysPlaying = editAdditionalAlwaysPlaying[toIdx]
            editAdditionalAlwaysPlaying[fromIdx] = toAlwaysPlaying
            editAdditionalAlwaysPlaying[toIdx] = fromAlwaysPlaying
        }
    }
} 