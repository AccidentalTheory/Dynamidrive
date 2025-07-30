import SwiftUI
import AVFoundation

struct AIConfigurePage: View {
    @Binding var showAIConfigurePage: Bool
    @Binding var showCreatePage: Bool
    @Binding var showVolumePage: Bool
    @Binding var createBaseAudioURL: URL?
    @Binding var createAdditionalZStacks: [ZStackData]
    @Binding var createAdditionalTitles: [String]
    @Binding var createAdditionalAlwaysPlaying: [Bool]
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
    @Binding var createSoundtrackTitle: String
    @Binding var createBaseTitle: String
    @Binding var selectedCardColor: Color
    var handleDoneAction: () -> Void
    
    @State private var showInfo2Page: Bool = false
    @State private var showColorPicker: Bool = false
    @State private var showOrderMenu: Bool = false
    @State private var orderMenuTarget: Int? = nil

    var body: some View {
        PageLayout(
            title: "AI Configure",
            leftButtonAction: { showColorPicker = true },
            rightButtonAction: { showInfo2Page = true },
            leftButtonSymbol: "paintbrush",
            rightButtonSymbol: "info",
            bottomButtons: [
                PageButton(label: { Image(systemName: "checkmark").globalButtonStyle() }, action: {
                    handleDoneAction()
                }),
                PageButton(label: { Image(systemName: "speaker.wave.3.fill").globalButtonStyle() }, action: {
                    if createBaseAudioURL == nil && createAdditionalZStacks.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    } else {
                        showVolumePage = true
                    }
                })
            ]
        ) {
            VStack() {
                configureHeader()
                configureAITrackList()
                Spacer().frame(height: 100)
            }
        }
        .sheet(isPresented: $showInfo2Page) {
            aiInfoPage()
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
            // Make placeholder buttons invisible
            DispatchQueue.main.async {
                // This will be handled by the PageLayout system
            }
        }
    }

    // MARK: - AI Configure Page Helper Functions
    func additionalAudioZStack(geometry: GeometryProxy?, index: Int) -> some View {
        var minSpeed: Binding<Int>
        var maxSpeed: Binding<Int>
        switch index {
        case 0:
            minSpeed = $createAudio1MinimumSpeed
            maxSpeed = $createAudio1MaximumSpeed
        case 1:
            minSpeed = $createAudio2MinimumSpeed
            maxSpeed = $createAudio2MaximumSpeed
        case 2:
            minSpeed = $createAudio3MinimumSpeed
            maxSpeed = $createAudio3MaximumSpeed
        case 3:
            minSpeed = $createAudio4MinimumSpeed
            maxSpeed = $createAudio4MaximumSpeed
        case 4:
            minSpeed = $createAudio5MinimumSpeed
            maxSpeed = $createAudio5MaximumSpeed
        default:
            minSpeed = .constant(0)
            maxSpeed = .constant(80)
        }
        
        let alwaysPlaying = Binding(
            get: { index < createAdditionalAlwaysPlaying.count ? createAdditionalAlwaysPlaying[index] : false },
            set: { newValue in
                while index >= createAdditionalAlwaysPlaying.count {
                    createAdditionalAlwaysPlaying.append(false)
                }
                createAdditionalAlwaysPlaying[index] = newValue
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
                    get: { index < createAdditionalTitles.count ? createAdditionalTitles[index] : "Audio \(index + 1)" },
                    set: { newValue in
                        while index >= createAdditionalTitles.count {
                            createAdditionalTitles.append("Audio \(createAdditionalTitles.count + 1)")
                            createAdditionalAlwaysPlaying.append(false)
                        }
                        createAdditionalTitles[index] = newValue
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
            // Order Button Menu (top right, aligned with infinity button)
            HStack {
                Spacer()
                Menu {
                    Button(action: { swapBaseWithDynamic(index) }) {
                        Text("Base")
                    }
                    ForEach(0..<createAdditionalTitles.count, id: \.self) { i in
                        Button(action: { swapBaseWithDynamic(i) }) {
                            Text("Track \(i + 1)")
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
    }
    
    @ViewBuilder
    private func configureHeader() -> some View {
        ZStack {
            GlobalCardAppearance
            TextField("Soundtrack Title", text: $createSoundtrackTitle)
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
    private func configureAITrackList() -> some View {
        VStack(spacing: 20) {
            if createBaseAudioURL != nil {
                ZStack(alignment: .center) {
                    GlobalCardAppearance
                    VStack(spacing: 0) {
                        TextField("Base", text: $createBaseTitle)
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
                            Button(action: { /* Already base, do nothing */ }) {
                                Text("Base")
                            }
                            ForEach(0..<createAdditionalTitles.count, id: \.self) { i in
                                Button(action: { swapBaseWithDynamic(i) }) {
                                    Text("Track \(i + 1)")
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
                .frame(height: 108)
                .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
            }
            
            ForEach(Array(createAdditionalZStacks.enumerated()), id: \.element.id) { index, stack in
                if stack.audioURL != nil {
                    additionalAudioZStack(geometry: nil, index: index)
                        .frame(height: 160)
                        .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
                }
            }
        }
    }

    // MARK: AI Info Page
    private func aiInfoPage() -> some View {
        Color(red: 26/255, green: 20/255, blue: 26/255)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                VStack(alignment: .leading, spacing: 20) {
                    Text("AI Separation Info")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Your audio has been separated into:")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "drumsticks")
                                .foregroundColor(.white)
                            Text("Drums - Base track")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.white)
                            Text("Bass - Dynamic track 1")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Image(systemName: "person.wave.2")
                                .foregroundColor(.white)
                            Text("Vocals - Dynamic track 2")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundColor(.white)
                            Text("Other instruments - Dynamic track 3")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 20)
                    
                    Text("All tracks are automatically synchronized and ready for speed-based playback.")
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .padding(.top, 10)
                    
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
                        selectedCardColor = color
                    }) {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(color == .clear ? Color.gray.opacity(0.1) : color)
                            .frame(height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white, lineWidth: selectedCardColor == color ? 3 : 0)
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
                        .glassEffect(.regular.tint(selectedCardColor == .clear ? .clear : selectedCardColor).interactive(), in: .rect(cornerRadius: 20.0))
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(createSoundtrackTitle.isEmpty ? "Soundtrack Title" : createSoundtrackTitle)
                                    .foregroundColor(.white)
                                    .font(.system(size: 28, weight: .semibold))
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                    .minimumScaleFactor(0.3)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(1)
                                
                                Text("Distance Played: 0 mi")
                                    .foregroundColor(selectedCardColor == .clear ? .gray : .white)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        
                        // Fake play button
                        if selectedCardColor == .clear {
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

    // Add swapBaseWithDynamic logic
    private func swapBaseWithDynamic(_ dynamicIdx: Int) {
        // Swap all relevant state between base and dynamicIdx
        // Save base
        let oldBaseTitle = createBaseTitle
        // Save dynamic
        let dynamicTitle = createAdditionalTitles[dynamicIdx]
        // Swap titles
        createBaseTitle = dynamicTitle
        createAdditionalTitles[dynamicIdx] = oldBaseTitle
        // Swap alwaysPlaying
        if dynamicIdx < createAdditionalAlwaysPlaying.count {
            let oldBaseAlways = createAdditionalAlwaysPlaying[dynamicIdx]
            createAdditionalAlwaysPlaying[dynamicIdx] = false
            // Optionally handle alwaysPlaying for base if needed
        }
        // Swap ZStackData
        if dynamicIdx < createAdditionalZStacks.count {
            var baseZStack = ZStackData(id: -1)
            baseZStack.audioURL = createBaseAudioURL
            baseZStack.player = nil
            baseZStack.isPlaying = false
            baseZStack.showingFilePicker = false
            baseZStack.offset = 0
            baseZStack.volume = 0.0
            // Swap
            let temp = createAdditionalZStacks[dynamicIdx]
            createBaseAudioURL = temp.audioURL
            createAdditionalZStacks[dynamicIdx] = baseZStack
        }
    }

    // MARK: - Track Reordering
    private func moveTrack(at source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < createAdditionalZStacks.count,
              destination >= 0, destination < createAdditionalZStacks.count else { return }
        // Move ZStackData
        let zStack = createAdditionalZStacks.remove(at: source)
        createAdditionalZStacks.insert(zStack, at: destination)
        // Move Titles
        if source < createAdditionalTitles.count {
            let title = createAdditionalTitles.remove(at: source)
            createAdditionalTitles.insert(title, at: destination)
        }
        // Move AlwaysPlaying
        if source < createAdditionalAlwaysPlaying.count {
            let always = createAdditionalAlwaysPlaying.remove(at: source)
            createAdditionalAlwaysPlaying.insert(always, at: destination)
        }
        // Move speed values if needed (optional, for 5-track limit)
        let minSpeeds = [
            $createAudio1MinimumSpeed, $createAudio2MinimumSpeed, $createAudio3MinimumSpeed, $createAudio4MinimumSpeed, $createAudio5MinimumSpeed
        ]
        let maxSpeeds = [
            $createAudio1MaximumSpeed, $createAudio2MaximumSpeed, $createAudio3MaximumSpeed, $createAudio4MaximumSpeed, $createAudio5MaximumSpeed
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
} 