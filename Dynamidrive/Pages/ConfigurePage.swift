import SwiftUI
import AVFoundation

struct ConfigurePage: View {
    @Binding var showConfigurePage: Bool
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

    var body: some View {
        PageLayout(
            title: "Configure",
            leftButtonAction: { showColorPicker = true },
            rightButtonAction: { showInfo2Page = true },
            leftButtonSymbol: "paintbrush",
            rightButtonSymbol: "info",
            bottomButtons: [
                PageButton(label: { Image(systemName: "arrow.uturn.backward").globalButtonStyle() }, action: {
                    showConfigurePage = false
                    showCreatePage = true
                    print("Back button pressed: showConfigurePage = false, showCreatePage = true")
                }),
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
                configureTrackList()
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
            // Make placeholder buttons invisible
            DispatchQueue.main.async {
                // This will be handled by the PageLayout system
            }
        }
    }

    // MARK: - Configure Page Helper Functions
    func additionalAudioZStack(geometry: GeometryProxy, index: Int) -> some View {
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
        
        return ZStack {
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
    private func configureTrackList() -> some View {
        VStack(spacing: 10) {
            if createBaseAudioURL != nil {
                GeometryReader { geometry in
                    ZStack {
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
                    }
                }
                .frame(height: 108)
                .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
            }
            ForEach(Array(createAdditionalZStacks.enumerated()), id: \ .element.id) { index, stack in
                if stack.audioURL != nil {
                    GeometryReader { geometry in
                        additionalAudioZStack(geometry: geometry, index: index)
                    }
                    .frame(height: 160)
                }
            }
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

    // MARK: Info2 Page
    private func info2Page() -> some View {
        Color(red: 26/255, green: 20/255, blue: 26/255)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                VStack(alignment: .leading, spacing: 20) {
                    Text("Configure Page Info")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundColor(.white)
                    Text("Add your content here...")
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
}
