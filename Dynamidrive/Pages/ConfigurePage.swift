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
    
    var handleDoneAction: () -> Void
    
    var body: some View {
        ZStack {
            // Scrollable content
            ScrollView {
                VStack(spacing: 20) {
                    configureHeader()
                    configureTrackList()
                    Spacer().frame(height: 100) // Add space at bottom for buttons
                }
                .padding()
                .offset(y: -15)
            }

            // Empty stack between content and buttons
            ZStack {
            }
            .frame(height: 150)
            .allowsHitTesting(false)

            // Fixed bottom controls
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        showConfigurePage = false
                        showCreatePage = true
                        print("Back button pressed: showConfigurePage = false, showCreatePage = true")
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    
                    Button(action: {
                        handleDoneAction()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 50)
                      
                            .clipShape(Capsule())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    
                    Button(action: {
                        if createBaseAudioURL == nil && createAdditionalZStacks.isEmpty {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        } else {
                            showVolumePage = true
                        }
                    }) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
        .zIndex(3)
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
                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading) // 65% of screen width
                .minimumScaleFactor(0.3) // Allows shrinking to 50% of size if needed
                .multilineTextAlignment(.leading) // Left-align new lines
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
    }
    
    @ViewBuilder
    private func configureHeader() -> some View {
        HStack {
            Text("Configure")
                .font(.system(size: 35, weight: .medium))
                .foregroundColor(.white)
            Spacer()
        }
        TextField("New Soundtrack", text: $createSoundtrackTitle)
            .font(.system(size: 30, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: 50)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.3))
            .cornerRadius(8)
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
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading) // 65% of screen width
                                .minimumScaleFactor(0.3) // Allows shrinking to 50% of size if needed
                                .multilineTextAlignment(.leading) // Left-align new lines
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
                        }
                    }
                }
                .frame(height: 108)
            }
            ForEach(Array(createAdditionalZStacks.enumerated()), id: \.element.id) { index, stack in
                if stack.audioURL != nil {
                    GeometryReader { geometry in
                        additionalAudioZStack(geometry: geometry, index: index)
                    }
                    .frame(height: 160)
                }
            }
        }
    }
}
