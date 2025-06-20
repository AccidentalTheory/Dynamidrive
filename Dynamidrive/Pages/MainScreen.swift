import SwiftUI
import AVFoundation
import UIKit

struct MainScreen: View {
    @Binding var currentPage: AppPage
    @Binding var showCreatePage: Bool
    @Binding var showImportPage: Bool
    @Binding var importedSoundtrackURL: URL?
    @Binding var showPlaybackPage: Bool
    @Binding var pendingSoundtrack: Soundtrack?
    @Binding var soundtracks: [Soundtrack]
    @Binding var isMainScreenEditMode: Bool
    @Binding var soundtracksBeingDeleted: Set<UUID>
    @EnvironmentObject private var audioController: AudioController
    @Binding var previousPage: AppPage?
    
    var resetCreatePage: () -> Void
    var deleteSoundtrack: (Soundtrack) -> Void
    
    var body: some View {
        ZStack {
            // Main Content
            VStack(spacing: 40) {
                if soundtracks.isEmpty {
                    Spacer()
                    VStack(spacing: 0) {
                        Image(systemName: "plus")
                            .font(.system(size: 160))
                            .foregroundColor(.white)
                            .opacity(0.4)
                            .frame(width: 180, height: 180)
                        Text("Press the new button to make your first soundtrack")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                            .opacity(0.4)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    Spacer()
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            Color.clear.frame(height: UIScreen.main.bounds.height * 0.08)
                            ForEach(soundtracks) { soundtrack in
                                soundtrackCard(soundtrack: soundtrack)
                                    .frame(height: 108)
                                    .padding(.horizontal)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: soundtracks)
                        .padding(.bottom, 100)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Header Layer
            VStack {
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentPage = .masterSettings
                        }
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                    Spacer()
                    Text("Dynamidrive")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        isMainScreenEditMode.toggle()
                    }) {
                        Image(systemName: isMainScreenEditMode ? "checkmark" : "minus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(isMainScreenEditMode ? .gray : .white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                            .glassEffect(.regular.tint(.clear).interactive())
                    }
                }
                .padding(.horizontal)
                .padding(.top, UIScreen.main.bounds.height * 0.01)
                Spacer()
            }
            
            // Bottom Buttons Container
            if !soundtracks.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                resetCreatePage()
                                showCreatePage = true
                                showImportPage = false
                                importedSoundtrackURL = nil
                                currentPage = .create
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                                .glassEffect(.regular.tint(.clear).interactive())
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private func soundtrackCard(soundtrack: Soundtrack) -> some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .background(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.4))
                .frame(height: 108)
                .cornerRadius(16)
            Button(action: {
                pendingSoundtrack = soundtrack
                previousPage = currentPage
                withAnimation(.easeInOut(duration: 0.5)) {
                    showPlaybackPage = true
                }
            }) {
                Text(soundtrack.title)
                    .foregroundColor(.white)
                    .font(.system(size: 35, weight: .semibold))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading) // 65% of screen width
                    .minimumScaleFactor(0.3) // Allows shrinking to 50% of size if needed
                    .multilineTextAlignment(.leading) // Left-align new lines
                    .lineLimit(2)
                    .offset(x:-40)
                    .padding(.leading, 16)
            }
            if isMainScreenEditMode {
                Button(action: {
                    // Mark the soundtrack as being deleted
                    soundtracksBeingDeleted.insert(soundtrack.id)
                    // Animate the fade-out and then delete
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // The opacity will change due to the binding in the modifier below
                    }
                    // Delay the actual deletion until the animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        deleteSoundtrack(soundtrack)
                        soundtracksBeingDeleted.remove(soundtrack.id)
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
            } else {
                Button(action: {
                    if audioController.currentSoundtrackTitle != soundtrack.title {
                        if audioController.isSoundtrackPlaying {
                            audioController.toggleSoundtrackPlayback()
                        }
                        audioController.setCurrentSoundtrack(tracks: soundtrack.tracks, players: soundtrack.players, title: soundtrack.title)
                        audioController.toggleSoundtrackPlayback()
                    } else {
                        audioController.toggleSoundtrackPlayback()
                    }
                }) {
                    Image(systemName: audioController.isSoundtrackPlaying && audioController.currentSoundtrackTitle == soundtrack.title ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
            }
        }
        .opacity(soundtracksBeingDeleted.contains(soundtrack.id) ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: soundtracksBeingDeleted)
    }
} 
