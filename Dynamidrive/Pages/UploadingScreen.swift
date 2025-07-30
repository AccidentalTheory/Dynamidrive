import SwiftUI

struct UploadingScreen: View {
    @Binding var isVisible: Bool
    @Binding var isUploading: Bool
    @Binding var isDownloading: Bool
    @State private var downloadProgress: Double = 0.0
    @State private var opacity: Double = 0.0
    @State private var shimmerOffset: CGFloat = -1.0
    let baseColor = Color(white: 0.3)
    let shimmerColor = Color.white
    let shimmerDuration = 1.2
    let uploadingPhrases = [
        "Sit back and relax, this might take a while.",
        "One sec...",
        "In the meantime, check out ButterDogCo.",
        "Still working...",
        "Stay tuned, we're still working"
    ]
    @State private var selectedPhrase: String = ""
    @State private var phraseTimer: Timer? = nil
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all, edges: .all)
            MeshGradientView()
                .ignoresSafeArea(.all, edges: .all)
            VStack {
                Spacer()
                ZStack {
                    if isDownloading {
                        // Progress-based text for downloading
                        Text("Downloading...")
                            .font(.title)
                            .foregroundColor(baseColor)
                            .multilineTextAlignment(.center)
                        Text("Downloading...")
                            .font(.title)
                            .foregroundColor(shimmerColor)
                            .multilineTextAlignment(.center)
                            .mask(
                                GeometryReader { geo in
                                    Rectangle()
                                        .frame(width: geo.size.width * downloadProgress, height: geo.size.height)
                                }
                            )
                    } else {
                        // Regular text for other states
                        Text(isUploading ? "Uploading..." : "Processing...")
                            .font(.title)
                            .foregroundColor(baseColor)
                            .multilineTextAlignment(.center)
                        Text(isUploading ? "Uploading..." : "Processing...")
                            .font(.title)
                            .foregroundColor(shimmerColor)
                            .multilineTextAlignment(.center)
                            .mask(
                                GeometryReader { geo in
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .clear, location: 0.0),
                                            .init(color: .white.opacity(0.5), location: 0.45),
                                            .init(color: .white, location: 0.5),
                                            .init(color: .white.opacity(0.5), location: 0.55),
                                            .init(color: .clear, location: 1.0)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .offset(x: geo.size.width * shimmerOffset)
                                }
                            )
                                                        .animation(.linear(duration: shimmerDuration).repeatForever(autoreverses: false), value: shimmerOffset)
                    }
                }
                if !isUploading && !isDownloading {
                    Text(selectedPhrase)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .opacity(selectedPhrase.isEmpty ? 0 : 1)
                        .animation(.easeIn(duration: 0.5), value: selectedPhrase)
                        .onAppear {
                            startPhraseTimer()
                        }
                        .onDisappear {
                            stopPhraseTimer()
                        }
                }
                Spacer()
            }
        }
        .opacity(opacity)
        .ignoresSafeArea(.all, edges: .all)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            if !isUploading {
                selectedPhrase = uploadingPhrases.randomElement() ?? "Please wait..."
                startPhraseTimer()
            }
            withAnimation(.easeIn(duration: 0.5)) {
                opacity = 1.0
            }
            shimmerOffset = -1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                shimmerOffset = 1.0
            }
        }
        .onChange(of: isVisible) { newValue in
            if !newValue {
                withAnimation(.easeOut(duration: 0.5)) {
                    opacity = 0.0
                }
                stopPhraseTimer()
            }
        }
        .onChange(of: isUploading) { newValue in
            if newValue {
                // Switched to uploading, stop timer and clear phrase
                stopPhraseTimer()
                selectedPhrase = ""
            } else {
                // Switched to processing, start timer and pick phrase
                selectedPhrase = uploadingPhrases.randomElement() ?? "Please wait..."
                startPhraseTimer()
            }
        }
        .onChange(of: isDownloading) { newValue in
            if newValue {
                // Switched to downloading, stop timer and clear phrase
                stopPhraseTimer()
                selectedPhrase = ""
                downloadProgress = 0.0 // Reset progress
            } else {
                // Switched to processing, start timer and pick phrase
                selectedPhrase = uploadingPhrases.randomElement() ?? "Please wait..."
                startPhraseTimer()
            }
        }
        .onDisappear {
            opacity = 0.0 // Reset for next appearance
            shimmerOffset = -1.0
            selectedPhrase = ""
            stopPhraseTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiDownloadProgress)) { notification in
            if let progress = notification.object as? Double {
                downloadProgress = progress
            }
        }
    }
    func startPhraseTimer() {
        stopPhraseTimer()
        phraseTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            if !isUploading {
                var newPhrase: String
                repeat {
                    newPhrase = uploadingPhrases.randomElement() ?? "Please wait..."
                } while newPhrase == selectedPhrase && uploadingPhrases.count > 1
                selectedPhrase = newPhrase
            }
        }
    }
    func stopPhraseTimer() {
        phraseTimer?.invalidate()
        phraseTimer = nil
    }
}
