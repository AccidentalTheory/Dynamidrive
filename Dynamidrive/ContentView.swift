import SwiftUI
import CoreLocation
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import MediaPlayer
import Glur
import MapKit
import TipKit

// MARK: - Audio Controller
class AudioController: ObservableObject {
    @Published var isSoundtrackPlaying: Bool = false
    @Published var masterPlaybackTime: TimeInterval = 0
    @Published var currentSoundtrackTitle: String = ""
    public var currentPlayers: [AVAudioPlayer?] = []
    public var currentTracks: [AudioController.SoundtrackData] = []
    private var syncTimer: Timer?
    private var locationHandler: LocationHandler
    
    struct SoundtrackData: Codable {
        let audioFileName: String
        let displayName: String
        let maximumVolume: Float
        let minimumSpeed: Int
        let maximumSpeed: Int
    }
    
    
    
    
    init(locationHandler: LocationHandler) {
        self.locationHandler = locationHandler
        setupAudioSession()
        setupRemoteControl()
    }
    
    // Add this new method to adjust volumes based on speed
    func adjustVolumesForSpeed(_ speed: Double) {
        guard isSoundtrackPlaying else { return }
        for (index, player) in currentPlayers.enumerated() {
            if let player = player, player.isPlaying {
                let targetVolume = calculateVolumeForTrack(at: index, speed: speed)
                fadeVolume(for: player, to: targetVolume, duration: 1.0)
            }
        }
        updateNowPlayingInfo()
    }
    
    // Existing methods below remain unchanged
    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured for background playback and Now Playing controls")
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func setupRemoteControl() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self, !self.isSoundtrackPlaying else { return .commandFailed }
            self.toggleSoundtrackPlayback()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self, self.isSoundtrackPlaying else { return .commandFailed }
            self.toggleSoundtrackPlayback()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.toggleSoundtrackPlayback()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }
    
    func updateNowPlayingInfo() {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()
        
        if isSoundtrackPlaying {
            nowPlayingInfo[MPMediaItemPropertyTitle] = currentSoundtrackTitle
            nowPlayingInfo[MPMediaItemPropertyArtist] = "Speed: \(Int(locationHandler.speedMPH.rounded())) mph"
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Dynamidrive Soundtracks"
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = masterPlaybackTime
            
            if let player = currentPlayers.first, let duration = player?.duration {
                nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            }
            
            if let appIcon = UIImage(named: "AlbumArt") {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: appIcon.size) { _ in appIcon }
            } else if let fallbackIcon = UIImage(systemName: "music.note")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: fallbackIcon.size) { _ in fallbackIcon }
            }
            
            nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        } else {
            nowPlayingInfoCenter.nowPlayingInfo = nil
        }
    }
    
    func toggleSoundtrackPlayback() {
        if isSoundtrackPlaying {
            if let firstPlayer = currentPlayers.first(where: { $0?.isPlaying ?? false }) {
                masterPlaybackTime = firstPlayer?.currentTime ?? 0.0
            }
            currentPlayers.forEach { $0?.pause() }
            updateSyncTimer()
        } else {
            let deviceCurrentTime = currentPlayers.first(where: { $0 != nil })??.deviceCurrentTime ?? 0
            let startTime = deviceCurrentTime + 0.1
            
            for (index, player) in currentPlayers.enumerated() {
                if let player = player {
                    player.currentTime = masterPlaybackTime // Use masterPlaybackTime, which may be 0 after rewind
                    player.numberOfLoops = -1
                    player.volume = calculateVolumeForTrack(at: index, speed: locationHandler.speedMPH)
                    player.play(atTime: startTime)
                }
            }
            updateSyncTimer()
        }
        isSoundtrackPlaying.toggle()
        updateNowPlayingInfo()
    }
    
    func setCurrentSoundtrack(tracks: [SoundtrackData], players: [AVAudioPlayer?], title: String) {
        if currentSoundtrackTitle == title && isSoundtrackPlaying {
            return
        } else if currentSoundtrackTitle != title {
            if isSoundtrackPlaying {
                currentPlayers.forEach { $0?.pause() }
                updateSyncTimer()
                isSoundtrackPlaying = false
            }
            masterPlaybackTime = 0
        }
        currentTracks = tracks
        currentPlayers = players
        currentSoundtrackTitle = title
        updateNowPlayingInfo()
    }
    
    private func updateSyncTimer() {
        let isAnyPlaying = isSoundtrackPlaying
        
        if isAnyPlaying && syncTimer == nil {
            syncTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.isSoundtrackPlaying {
                    if let firstPlayer = self.currentPlayers.first(where: { $0?.isPlaying ?? false }) {
                        self.masterPlaybackTime = firstPlayer?.currentTime ?? 0.0
                        for player in self.currentPlayers {
                            if let player = player, player.isPlaying {
                                player.currentTime = self.masterPlaybackTime
                            }
                        }
                    }
                }
                self.updateNowPlayingInfo()
            }
        } else if !isAnyPlaying && syncTimer != nil {
            syncTimer?.invalidate()
            syncTimer = nil
            masterPlaybackTime = 0
            updateNowPlayingInfo()
        }
    }
    
    func calculateVolumeForTrack(at index: Int, speed: Double) -> Float {
        guard index < currentTracks.count else { return 0.0 }
        let track = currentTracks[index]
        
        if index == 0 {
            return mapVolume(track.maximumVolume)
        }
        
        let minSpeed = Double(track.minimumSpeed)
        let maxSpeed = Double(track.maximumSpeed)
        let maxVolume = mapVolume(track.maximumVolume)
        
        if minSpeed == maxSpeed {
            return maxVolume
        }
        
        guard minSpeed < maxSpeed else { return 0.0 }
        
        if speed < minSpeed {
            return 0.0
        } else if speed >= maxSpeed {
            return maxVolume
        } else {
            let speedRange = maxSpeed - minSpeed
            let progress = (speed - minSpeed) / speedRange
            return Float(progress) * maxVolume
        }
    }
    
    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
    }
    
    func fadeVolume(for player: AVAudioPlayer?, to targetVolume: Float, duration: TimeInterval = 1.0) {
        guard let player = player else { return }
        let steps = 20
        let stepInterval = duration / Double(steps)
        let startVolume = player.volume
        let volumeStep = (targetVolume - startVolume) / Float(steps)
        
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepInterval * Double(i)) {
                player.volume = max(0.0, min(2.0, startVolume + volumeStep * Float(i)))
            }
        }
    }
}

// MARK: - Soundtrack Struct
struct Soundtrack: Identifiable, Codable {
    let id: UUID
    let title: String
    let tracks: [AudioController.SoundtrackData]
    var players: [AVAudioPlayer?] {
        didSet {
            for player in players {
                player?.prepareToPlay()
            }
        }
    }
    

    
    // Custom coding keys to exclude players
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case tracks
    }
    
    // Custom initializer for decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.tracks = try container.decode([AudioController.SoundtrackData].self, forKey: .tracks)
        self.players = [] // Initialize as empty; will be set during loadSoundtracks
    }
    
    // Custom initializer for encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(tracks, forKey: .tracks)
        // players is not encoded
    }
    
    // Convenience initializer for creating a new Soundtrack
    init(id: UUID, title: String, tracks: [AudioController.SoundtrackData], players: [AVAudioPlayer?]) {
        self.id = id
        self.title = title
        self.tracks = tracks
        self.players = players
    }
}


class AppDelegate: NSObject, UIApplicationDelegate {
    let audioController: AudioController
    private let locationHandler = LocationHandler()
    
    override init() {
        self.audioController = AudioController(locationHandler: locationHandler)
        super.init()
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        locationHandler.startLocationUpdates()
        return true
    }
}

extension Soundtrack: Equatable {
    static func == (lhs: Soundtrack, rhs: Soundtrack) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.tracks == rhs.tracks
    }
}

extension AudioController.SoundtrackData: Equatable {
    static func == (lhs: AudioController.SoundtrackData, rhs: AudioController.SoundtrackData) -> Bool {
        return lhs.audioFileName == rhs.audioFileName &&
               lhs.displayName == rhs.displayName &&
               lhs.maximumVolume == rhs.maximumVolume &&
               lhs.minimumSpeed == rhs.minimumSpeed &&
               lhs.maximumSpeed == rhs.maximumSpeed
    }
}

//MARK: Tips
struct CreatePageTip: Tip {
    var title: Text {
        Text("Create a soundtrack with AI")
    }
    
    var message: Text? {
        Text("Upload one file and tracks with different instruments will be generated for you.")
    }
    
    var image: Image? {
        Image(systemName: "sparkles")
    }
}

struct EditPageTip: Tip {
    var title: Text {
        Text("Edit soundtrack")
    }
    
    var message: Text? {
        Text("You can edit a soundtrack at any time")
    }
    
    var image: Image? {
        Image(systemName: "slider.horizontal.3")
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var isLoading = true
    @State private var showCreatePage = false
    @State private var showVolumePage = false
    @State private var showInfoPage = false
    @State private var showConfigurePage = false
    @State private var showPlaybackPage = false
    @State private var showEditPage = false
    @State private var showEditConfigurePage = false
    @State private var showSpeedDetailPage = false // New state for speed detail page
    @StateObject private var locationHandler = LocationHandler()
    @EnvironmentObject private var audioController: AudioController
    @State private var soundtracks: [Soundtrack] = []
    @State private var displayedSpeed: Int = 0 // For the numerical display (no animation)
    @State private var animatedSpeed: Double = 0.0 // For the gauge (with animation)
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCompletedInitialLoad = false
    @State private var isReturningFromConfigure = false
    @State private var createPageRemovalDirection: Edge = .leading
    @State private var volumePageRemovalDirection: Edge = .leading
    @State private var configurePageInsertionDirection: Edge = .trailing
    @State private var shouldResetPlaybackPage = false
    @State private var createPageInsertionDirection: Edge = .trailing
    @State private var playbackPageInsertionDirection: Edge = .trailing
    @State private var playbackPageRemovalDirection: Edge = .trailing
    @State private var configurePageRemovalDirection: Edge = .leading
    @State private var soundtracksBeingDeleted: Set<UUID> = []
    @State private var minSpeedScale: [Int: CGFloat] = [:] // Track scale for minimum speed per index
    @State private var maxSpeedScale: [Int: CGFloat] = [:] // Track scale for maximum speed per index
    @State private var minSpeedBelow: [Int: Bool] = [:]    // Track if speed is below minimum per index
    @State private var maxSpeedBelow: [Int: Bool] = [:]    // Track if speed is below maximum per index
    @State private var isRewindShowingCheckmark = false
    @State private var pendingSoundtrack: Soundtrack?
    @State private var editingSoundtrack: Soundtrack?
    @State private var createBaseAudioURL: URL?
    @State private var createBasePlayer: AVAudioPlayer?
    @State private var createBaseIsPlaying = false
    @State private var createBaseOffset: CGFloat = 0
    @State private var createBaseShowingFilePicker = false
    @State private var createBaseVolume: Float = 0.0
    @State private var createBaseTitle: String = "Base"
    @State private var createAdditionalZStacks: [ZStackData] = []
    @State private var createAdditionalTitles: [String] = []
    @State private var createAdditionalAlwaysPlaying: [Bool] = []
    @State private var createSoundtrackTitle: String = "New Soundtrack"
    @State private var createReferenceLength: TimeInterval?
    @State private var createNextID = 1
    @State private var createAudio1MinimumSpeed: Int = 0
    @State private var createAudio1MaximumSpeed: Int = 80
    @State private var createAudio2MinimumSpeed: Int = 0
    @State private var createAudio2MaximumSpeed: Int = 80
    @State private var createAudio3MinimumSpeed: Int = 0
    @State private var createAudio3MaximumSpeed: Int = 80
    @State private var createAudio4MinimumSpeed: Int = 0
    @State private var createAudio4MaximumSpeed: Int = 80
    @State private var createAudio5MinimumSpeed: Int = 0
    @State private var createAudio5MaximumSpeed: Int = 80
    @State private var areButtonsVisible: Bool = true // Controls visibility of buttons on speedDetailPage
    @State private var showSettingsPage: Bool = false // Controls visibility of the new settings page
    @State private var showPortraitSpeed: Bool = true
    @State private var showLandscapeSpeed: Bool = false
    @State private var showLengthMismatchAlert = false
    @State private var isSpinning = false
    @State private var showFirstLaunchAlert = false
    @State private var previewTrackingTimer: Timer?
    @State private var isMainScreenEditMode = false
    @State private var useGaugeWithValues: Bool = false
    @State private var gradientRotation: Double = 0 // New state for gradient rotation
    @State private var createTip = CreatePageTip()
    @State private var editTip = EditPageTip()
    
    // MARK: Gauge Settings
    @AppStorage("portraitGaugeStyle") private var portraitGaugeStyle: String = "fullCircle" // "fullCircle" or "separatedArc"
    @AppStorage("portraitIndicatorStyle") private var portraitIndicatorStyle: String = "line" // "line" or "dot"
    @AppStorage("portraitShowCurrentSpeed") private var portraitShowCurrentSpeed: Bool = true
    @AppStorage("portraitShowMinMax") private var portraitShowMinMax: Bool = false

    @AppStorage("landscapeGaugeStyle") private var landscapeGaugeStyle: String = "line" // "line" or "circular"
    @AppStorage("landscapeIndicatorStyle") private var landscapeIndicatorStyle: String = "fill" // "fill" or "dot" for line, "line" or "dot" for circular
    @AppStorage("landscapeShowCurrentSpeed") private var landscapeShowCurrentSpeed: Bool = true
    @AppStorage("landscapeShowMinMax") private var landscapeShowMinMax: Bool = false
    @AppStorage("landscapeShowSoundtrackTitle") private var landscapeShowSoundtrackTitle: Bool = true // New setting for soundtrack title
    @AppStorage("syncCircularGaugeSettings") private var syncCircularGaugeSettings: Bool = false // New setting for syncing

    @AppStorage("useBlackBackground") private var useBlackBackground: Bool = false
    @AppStorage("gaugeFontStyle") private var gaugeFontStyle: String = "default" // "default" or "rounded"
    
    // MARK: State for Orientation
    @State private var deviceOrientation: UIDeviceOrientation = .portrait
    
    enum AppPage: Equatable {
        case loading
        case main
        case create
        case configure
        case volume
        case playback
        case edit
        case speedDetail // New page type for speed detail
        case settings
    }

    @State private var currentPage: AppPage = .loading
    @State private var previousPage: AppPage? = nil
    
    struct ZStackData: Identifiable {
        let id: Int
        var offset: CGFloat = 0
        var audioURL: URL?
        var player: AVAudioPlayer?
        var isPlaying = false
        var showingFilePicker = false
        var volume: Float = 0.0
    }
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // MARK: Body
    var body: some View {
        ZStack {
            // Fixed map and blur background for all pages
            Map(position: $cameraPosition, interactionModes: []) {
                UserAnnotation()
            }
            .mapStyle(.standard)
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(.all)
            .onAppear {
                // Set initial camera position to follow user location
                cameraPosition = .userLocation(followsHeading: false, fallback: .camera(MapCamera(
                    centerCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                    distance: 1000,
                    heading: 0
                )))
            }
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(.all)
            
            // Handle initial load with opacity-based fade
            if !hasCompletedInitialLoad {
                loadingScreen
                    .zIndex(5)
                    .opacity(isLoading ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: isLoading)
                    
                mainScreen
                    .opacity(isLoading ? 0 : 1)
                    .animation(.easeInOut(duration: 0.5), value: isLoading)
            } else {
                // Show the current page (outgoing page during transition)
                Group {
                    switch currentPage {
                    case .loading:
                        loadingScreen
                            .zIndex(5)
                    case .main:
                        mainScreen
                            .transition(.asymmetric(insertion: isReturningFromConfigure ? .move(edge: .trailing) : (previousPage == .create || previousPage == .playback ? .move(edge: .leading) : .move(edge: .trailing)), removal: .move(edge: .leading)))
                    case .create:
                        createPage
                            .transition(.asymmetric(insertion: .move(edge: createPageInsertionDirection), removal: .move(edge: createPageRemovalDirection)))
                    case .configure:
                        configurePage
                            .transition(.asymmetric(insertion: .move(edge: configurePageInsertionDirection), removal: .move(edge: configurePageRemovalDirection)))
                    case .volume:
                        volumePage
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: volumePageRemovalDirection)))
                    case .playback:
                        playbackPage
                            .transition(.asymmetric(insertion: .move(edge: playbackPageInsertionDirection), removal: .move(edge: playbackPageRemovalDirection)))
                    case .edit:
                        editPage
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    case .speedDetail:
                        speedDetailPage
                            .transition(.asymmetric(
                                insertion: previousPage == .playback ? .move(edge: .trailing) : .move(edge: .leading),
                                removal: showSettingsPage ? .move(edge: .leading) : .move(edge: .trailing)
                            ))
                    case .settings:
                        settingsPage
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .trailing)
                            ))
                    }
                }
                .zIndex(9) // Current page is on top
            }
        }
        .statusBar(hidden: currentPage == .loading || currentPage == .speedDetail || !hasCompletedInitialLoad)
        .onAppear {
            // Lock to portrait orientation
            setDeviceOrientation(.portrait)
            isSpinning = true
            locationHandler.startLocationUpdates()
            loadSoundtracks()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isLoading = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    hasCompletedInitialLoad = true
                    currentPage = .main
                }
            }
            
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "hasLaunchedBefore") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                    showFirstLaunchAlert = true
                }
                defaults.set(true, forKey: "hasLaunchedBefore")
            }
        }
        .onChange(of: isLoading, initial: false) { _, newValue in
            if !newValue && !hasCompletedInitialLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    hasCompletedInitialLoad = true
                    currentPage = .main
                    isReturningFromConfigure = false
                    createPageRemovalDirection = .leading // Reset
                    volumePageRemovalDirection = .leading // Reset
                    configurePageInsertionDirection = .trailing // Reset
                }
            }
        }
        .onChange(of: showCreatePage, initial: false) { _, newValue in
            print("showCreatePage changed to: \(newValue), currentPage: \(currentPage), createPageRemovalDirection: \(createPageRemovalDirection)")
            createPageRemovalDirection = newValue ? .leading : .trailing
            print("createPageRemovalDirection set to: \(createPageRemovalDirection)")
            withAnimation(.easeInOut(duration: 0.5)) {
                let oldPage = currentPage
                previousPage = newValue ? oldPage : .create
                currentPage = newValue ? .create : .main
                isReturningFromConfigure = false
            }
            print("After showCreatePage change: currentPage: \(currentPage)")
        }
        .onChange(of: showConfigurePage, initial: false) { _, newValue in
            print("showConfigurePage changed to: \(newValue), currentPage: \(currentPage), showCreatePage: \(showCreatePage)")
            // Set directions before the animation starts
            if !newValue && currentPage == .configure && showCreatePage {
                configurePageRemovalDirection = .trailing // Configure slides out to right
                createPageInsertionDirection = .leading // Create slides in from left
                createPageRemovalDirection = .leading // Maintain default removal
                print("Set directions before transition - configurePageRemovalDirection: \(configurePageRemovalDirection), createPageInsertionDirection: \(createPageInsertionDirection)")
            }
            
            withAnimation(.easeInOut(duration: 0.5)) {
                let oldPage = currentPage
                print("oldPage: \(oldPage)")
                isReturningFromConfigure = !newValue
                previousPage = newValue ? oldPage : .configure
                if newValue {
                    // Going to configurePage, use default directions
                    currentPage = .configure
                    print("Navigating to configurePage - configurePageInsertionDirection: \(configurePageInsertionDirection), configurePageRemovalDirection: \(configurePageRemovalDirection)")
                } else {
                    // Returning from configurePage
                    if oldPage == .configure && showCreatePage {
                        // Returning to createPage
                        currentPage = .create
                        print("During transition to createPage - configurePageRemovalDirection: \(configurePageRemovalDirection), createPageInsertionDirection: \(createPageInsertionDirection)")
                    } else {
                        currentPage = .main
                        print("Returning to main - configurePageRemovalDirection: \(configurePageRemovalDirection)")
                    }
                }
                print("After showConfigurePage change: currentPage: \(currentPage), showCreatePage: \(showCreatePage)")
            }
            
            if !newValue && currentPage == .create {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    configurePageRemovalDirection = .leading // Restore default
                    createPageInsertionDirection = .trailing // Restore default
                    createPageRemovalDirection = .leading // Restore default
                    print("Reset directions after transition - configurePageRemovalDirection: \(configurePageRemovalDirection), createPageInsertionDirection: \(createPageInsertionDirection)")
                }
            }
        }
        .onChange(of: showVolumePage, initial: false) { oldValue, newValue in
            volumePageRemovalDirection = newValue ? .leading : .trailing
            configurePageInsertionDirection = newValue ? .trailing : .leading
            print("volumePageRemovalDirection set to: \(volumePageRemovalDirection), configurePageInsertionDirection set to: \(configurePageInsertionDirection)")
            withAnimation(.easeInOut(duration: 0.5)) {
                let oldPage = currentPage
                previousPage = newValue ? oldPage : .volume
                currentPage = newValue ? .volume : .configure
            }
        }
        .onChange(of: showPlaybackPage, initial: false) { _, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                let oldPage = currentPage
                previousPage = newValue ? oldPage : (oldPage == .volume ? .volume : .playback)
                currentPage = newValue ? .playback : previousPage == .volume ? .volume : .main
                isReturningFromConfigure = false
                volumePageRemovalDirection = .leading // Reset
                configurePageInsertionDirection = .trailing // Reset
            }
        }
        .onChange(of: locationHandler.speedMPH) { oldValue, newSpeed in
            // Update displayedSpeed immediately for the numerical display
            displayedSpeed = Int(newSpeed.rounded())
            
            // Animate animatedSpeed for the gauge
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedSpeed = newSpeed
            }
            
            // Adjust volumes for all playing tracks
            withAnimation(.easeInOut(duration: 1.0)) {
                for (index, player) in audioController.currentPlayers.enumerated() {
                    if let player = player, player.isPlaying {
                        let targetVolume = audioController.calculateVolumeForTrack(at: index, speed: newSpeed)
                        audioController.fadeVolume(for: player, to: targetVolume, duration: 1.0)
                    }
                }
            }
            if audioController.isSoundtrackPlaying {
                audioController.updateNowPlayingInfo()
            }
        }
        .onChange(of: showEditPage, initial: false) { _, newValue in
            if newValue {
                // Going to edit page: set removal direction before animation
                playbackPageRemovalDirection = .leading
                withAnimation(.easeInOut(duration: 0.5)) {
                    previousPage = currentPage
                    currentPage = .edit
                }
            } else {
                // Returning to playback page
                withAnimation(.easeInOut(duration: 0.5)) {
                    previousPage = .edit
                    currentPage = .playback
                    playbackPageInsertionDirection = .leading
                    playbackPageRemovalDirection = .trailing
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.playbackPageInsertionDirection = .trailing // Reset to default
                }
            }
        }
        .onChange(of: showSpeedDetailPage, initial: false) { _, newValue in
            if newValue {
                // Going to speed detail page
                playbackPageRemovalDirection = .leading
                withAnimation(.easeInOut(duration: 0.5)) {
                    previousPage = currentPage
                    currentPage = .speedDetail
                }
            } else {
                // Returning to playback page
                withAnimation(.easeInOut(duration: 0.5)) {
                    previousPage = .speedDetail
                    currentPage = .playback
                    playbackPageInsertionDirection = .leading
                    playbackPageRemovalDirection = .trailing
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.playbackPageInsertionDirection = .trailing // Reset to default
                }
            }
        }
        .onChange(of: showSettingsPage, initial: false) { _, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                if newValue {
                    previousPage = currentPage
                    currentPage = .settings
                } else {
                    currentPage = .speedDetail
                }
            }
        }
        .onChange(of: currentPage) { oldPage, newPage in
            // Enforce portrait orientation for playback and settings pages
            if newPage == .playback || newPage == .settings {
                setDeviceOrientation(.portrait)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if audioController.isSoundtrackPlaying {
                print("App moving to background, audio should continue playing with Now Playing controls")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if audioController.isSoundtrackPlaying {
                print("App returning to foreground, audio already playing with Now Playing controls")
            }
        }
        .alert(isPresented: $showFirstLaunchAlert) {
            Alert(
                title: Text("Drive safely"),
                message: Text("Do not let this app distract your driving. Please pay attention to the road."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    
    // MARK: Main Page
    private var mainScreen: some View {
        ZStack {
            VStack(spacing: 40) {
                HStack {
                    Text("Dynamidrive")
                        .font(.system(size: 35, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        resetCreatePage()
                        showCreatePage = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 17))
                            Text("New")
                                .font(.system(size: 15, weight: .regular))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(width: 82, height: 35)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, -15)
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
                    Spacer()
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 10) {
                            ForEach(soundtracks) { soundtrack in
                                soundtrackCard(soundtrack: soundtrack)
                                    .frame(height: 108)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: soundtracks)
                    }
                    .frame(maxWidth: .infinity)
                    .clipped(antialiased: false)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // Edit Button with Haptic Feedback
            if !soundtracks.isEmpty {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    isMainScreenEditMode.toggle()
                }) {
                    Image(systemName: isMainScreenEditMode ? "checkmark" : "minus.circle")
                        .font(.system(size: 24))
                        .foregroundColor(isMainScreenEditMode ? .gray : .white)
                        .frame(width: 50, height: 50)
                        .background(isMainScreenEditMode ? Color.white.opacity(1) : Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
    
    private func soundtrackCard(soundtrack: Soundtrack) -> some View {
        ZStack {
            Color(red: 0/255, green: 0/255, blue: 0/255)
                .opacity(0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                )
                .frame(height: 108)
                .cornerRadius(16)
            Button(action: {
                pendingSoundtrack = soundtrack
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
    
    // MARK: - Loading Screen
    private var loadingScreen: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all)
            
            Image("Spinning")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(isSpinning ? -360 : 0))
                .animation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: isSpinning
                )
                .opacity(isLoading ? 1 : 0)
            
            Image("Fixed")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .opacity(isLoading ? 1 : 0)
        }
        .zIndex(5)
        .opacity(currentPage == .loading ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: currentPage)
    }
    
    // MARK: - Create Page
    private var createPage: some View {
        createPageContent
            .zIndex(1)
    }
    
    private var createPageBackground: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                LinearGradient(
                    gradient: Gradient(colors: [Color(.darkGray), .black]),
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 286 / geometry.size.height)
                )
                .frame(height: geometry.size.height)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    private var createPageContent: some View {
        ZStack {
            // Background content
            ScrollView {
                VStack(spacing: 40) {
                    HStack {
                        Text(createSoundtrackTitle)
                            .font(.system(size: 35, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            showInfoPage = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                        }
                    }
                    VStack(spacing: 10) {
                        baseAudioStack
                        dynamicAudioStacks
                        addAudioButton
                    }
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
            .glur(radius: 8.0,
                  offset: 0.3,
                  interpolation: 0.4,
                  direction: .down)

            // Fixed bottom controls
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        pauseAllAudio()
                        showCreatePage = false
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        if createBaseAudioURL != nil && createAdditionalZStacks.contains(where: { $0.audioURL != nil }) {
                            showConfigurePage = true
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }) {
                        Text("Next")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .opacity(createBaseAudioURL != nil && createAdditionalZStacks.contains(where: { $0.audioURL != nil }) ? 1.0 : 0.5)
                    
                    ZStack {
                        // Gradient image positioned directly behind the button
                        Image("Gradient")
                            .resizable()
                            .scaledToFit()
                            .opacity(1)
                            .frame(width: 115, height: 115)
                            .rotationEffect(.degrees(gradientRotation))
                            .onAppear {
                                withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                                    gradientRotation = 360
                                }
                            }
                        
                        Button(action: {
                            // Placeholder action for sparkles button
                        }) {
                            ZStack {
                                // White circle background
                                Circle()
                                    .fill(Color.white.opacity(0.6))
                                    .frame(width: 50, height: 50)
                                
                                // Gradient visible through the sparkles
                                Image("Gradient")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 115, height: 115)
                                    .rotationEffect(.degrees(gradientRotation))
                                    .mask(
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 20))
                                            .foregroundColor(.black)
                                    )
                            }
                        }
                        .popoverTip(createTip, arrowEdge: .bottom)
                    }
                    .frame(width: 50, height: 50)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
        .sheet(isPresented: $showInfoPage) {
            infoPage()
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            try? Tips.configure()
        }
    }
    
    private var baseAudioStack: some View {
        GeometryReader { geometry in
            baseAudioCard(geometry: geometry)
                .offset(x: createBaseOffset)
                .gesture(baseAudioGesture)
        }
        .frame(height: 108)
        .alert(isPresented: $showLengthMismatchAlert) {
            Alert(
                title: Text("Length Mismatch"),
                message: Text("All tracks should be the same length"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func baseAudioCard(geometry: GeometryProxy) -> some View {
        ZStack {
            Color(red: 0/255, green: 0/255, blue: 0/255)
                .opacity(0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                )
                .frame(width: geometry.size.width, height: 108)
                .cornerRadius(16)
                .clipped()
            Text(createBaseTitle)
                .font(.system(size: 35, weight: .semibold))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading) // 65% of screen width
                .minimumScaleFactor(0.3) // Allows shrinking to 50% of size if needed
                .multilineTextAlignment(.leading) // Left-align new lines
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
                Image(systemName: createBaseAudioURL == nil ? "plus" : (createBaseIsPlaying ? "pause" : "play"))
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
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
        DocumentPicker { url in
            if let storedURL = storeAudioFile(url, name: "Soundtrack\(soundtracks.count + 1)Base_\(UUID().uuidString)") {
                if let tempPlayer = try? AVAudioPlayer(contentsOf: storedURL) {
                    let duration = tempPlayer.duration
                    if createReferenceLength == nil || createAdditionalZStacks.isEmpty {
                        createReferenceLength = duration
                        createBaseAudioURL = storedURL
                        createBasePlayer = tempPlayer
                        createBasePlayer?.volume = mapVolume(createBaseVolume)
                        createBasePlayer?.prepareToPlay()
                    } else if abs(duration - createReferenceLength!) < 0.1 {
                        createBaseAudioURL = storedURL
                        createBasePlayer = tempPlayer
                        createBasePlayer?.volume = mapVolume(createBaseVolume)
                        createBasePlayer?.prepareToPlay()
                    } else {
                        removeAudioFile(at: storedURL)
                        showLengthMismatchAlert = true
                    }
                }
            }
        }
    }
    
    private var dynamicAudioStacks: some View {
        ForEach(createAdditionalZStacks.indices, id: \.self) { index in
            GeometryReader { geometry in
                dynamicAudioCard(geometry: geometry, index: index)
                    .offset(x: createAdditionalZStacks[index].offset)
                    .gesture(dynamicAudioGesture(index: index))
            }
            .frame(height: 108)
        }
    }
    
    private func dynamicAudioCard(geometry: GeometryProxy, index: Int) -> some View {
        ZStack {
            Color(red: 0/255, green: 0/255, blue: 0/255)
                .opacity(0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                )
                .frame(width: geometry.size.width, height: 108)
                .cornerRadius(16)
                .clipped()
            Text(index < createAdditionalTitles.count ? createAdditionalTitles[index] : "Audio \(index + 1)")
                .font(.system(size: 35, weight: .semibold))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading) // 65% of screen width
                .minimumScaleFactor(0.3) // Allows shrinking to 50% of size if needed
                .multilineTextAlignment(.leading) // Left-align new lines
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
                Image(systemName: createAdditionalZStacks[index].audioURL == nil ? "plus" : (createAdditionalZStacks[index].isPlaying ? "pause" : "play"))
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            .sheet(isPresented: Binding(
                get: { createAdditionalZStacks[index].showingFilePicker },
                set: { newValue in createAdditionalZStacks[index].showingFilePicker = newValue }
            )) {
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
        DocumentPicker { url in
            if let storedURL = storeAudioFile(url, name: "Soundtrack\(soundtracks.count + 1)Audio\(index + 1)_\(UUID().uuidString)") {
                if let tempPlayer = try? AVAudioPlayer(contentsOf: storedURL) {
                    let duration = tempPlayer.duration
                    if createReferenceLength == nil || abs(duration - createReferenceLength!) < 0.1 {
                        createAdditionalZStacks[index].audioURL = storedURL
                        createAdditionalZStacks[index].player = tempPlayer
                        createAdditionalZStacks[index].player?.volume = mapVolume(createAdditionalZStacks[index].volume)
                        createAdditionalZStacks[index].player?.prepareToPlay()
                        if createReferenceLength == nil {
                            createReferenceLength = duration
                        }
                    } else {
                        removeAudioFile(at: storedURL)
                        showLengthMismatchAlert = true
                    }
                }
            }
        }
    }
    
    private var addAudioButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                createAdditionalZStacks.append(ZStackData(id: createNextID))
                createAdditionalTitles.append("Audio \(createNextID)")
                createAdditionalAlwaysPlaying.append(false)
                createNextID += 1
            }
        }) {
            Image(systemName: "plus")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.2))
                .clipShape(Circle())
        }
        .padding(.top, 10)
    }
    
    // MARK: - Volume Page
    private var volumePage: some View {
        volumePageContent
            .zIndex(4)
    }
    
    private var volumePageContent: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Volume Control")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            VStack(spacing: 10) {
                if createBaseAudioURL != nil {
                    GeometryReader { geometry in
                        ZStack {
                            Color(red: 0/255, green: 0/255, blue: 0/255)
                                .opacity(0.3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                        )
                                .frame(width: geometry.size.width, height: 108)
                                .cornerRadius(16)
                                .clipped()
                            VStack(spacing: 4) {
                                Text(createBaseTitle)
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 16)
                                Slider(value: $createBaseVolume, in: -100...100, step: 1) { _ in
                                    if let player = createBasePlayer {
                                        player.volume = mapVolume(createBaseVolume)
                                    }
                                }
                                .frame(width: geometry.size.width * 0.7)
                            }
                        }
                    }
                    .frame(height: 108)
                }
                ForEach(createAdditionalZStacks.indices, id: \.self) { index in
                    if createAdditionalZStacks[index].audioURL != nil {
                        GeometryReader { geometry in
                            ZStack {
                                Color(red: 20/255, green: 20/255, blue: 20/255)
                                    .frame(width: geometry.size.width, height: 108)
                                    .cornerRadius(16)
                                    .clipped()
                                VStack(spacing: 4) {
                                    Text(index < createAdditionalTitles.count ? createAdditionalTitles[index] : "Audio \(index + 1)")
                                        .font(.system(size: 35, weight: .semibold))
                                        .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading) // 65% of screen width
                                        .minimumScaleFactor(0.3) // Allows shrinking to 50% of size if needed
                                        .multilineTextAlignment(.leading) // Left-align new lines
                                        .lineLimit(2)
                                        .offset(x:-40)
                                        .foregroundColor(.white)
                                        .padding(.leading, 16)
                                    Slider(value: Binding(
                                        get: { createAdditionalZStacks[index].volume },
                                        set: { createAdditionalZStacks[index].volume = $0 }
                                    ), in: -100...100, step: 1) { _ in
                                        if let player = createAdditionalZStacks[index].player {
                                            player.volume = mapVolume(createAdditionalZStacks[index].volume)
                                        }
                                    }
                                    .frame(width: geometry.size.width * 0.7)
                                }
                            }
                        }
                        .frame(height: 108)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .overlay(
            Button(action: {
                showVolumePage = false
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding()
        )
    }
    
    // MARK: Configure Page
    private var configurePage: some View {
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
            .glur(radius: 8.0,
                  offset: 0.3,
                  interpolation: 0.4,
                  direction: .down)

            // Fixed bottom controls
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        showConfigurePage = false
                        showCreatePage = true
                        print("Back button pressed: showConfigurePage = false, showCreatePage = true")
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        handleDoneAction()
                    }) {
                        Text("Done")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
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
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
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
            Color(red: 0/255, green: 0/255, blue: 0/255)
                .opacity(0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                        )
                .frame(width: geometry.size.width, height: 160)
                .cornerRadius(16)
                .clipped()
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
                    .background(alwaysPlaying.wrappedValue ? Color.white : Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 15)
            .padding(.bottom, 10)
            .offset(y: -12)
        }
        .animation(.easeInOut(duration: 0.3), value: alwaysPlaying.wrappedValue)
    }

    @ViewBuilder
    func configureHeader() -> some View {
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
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
    }

    @ViewBuilder
    func configureTrackList() -> some View {
        VStack(spacing: 10) {
            if createBaseAudioURL != nil {
                GeometryReader { geometry in
                    ZStack {
                        Color(red: 0/255, green: 0/255, blue: 0/255)
                            .opacity(0.3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                    )
                            .frame(width: geometry.size.width, height: 108)
                            .cornerRadius(16)
                            .clipped()
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
            ForEach(createAdditionalZStacks.indices, id: \.self) { index in
                if createAdditionalZStacks[index].audioURL != nil {
                    GeometryReader { geometry in
                        additionalAudioZStack(geometry: geometry, index: index)
                    }
                    .frame(height: 160)
                }
            }
        }
    }
    
    // MARK: Playback Page
    private var playbackPage: some View {
        @ViewBuilder
        func speedGauge(geometry: GeometryProxy, displayedSpeed: Int, animatedSpeed: Binding<Double>) -> some View {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showSpeedDetailPage = true
                }
            }) {
                HStack(spacing: 10) {
                    Text("Speed")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 100, alignment: .leading)
                        .offset(x: -3)
                    Spacer()
                    Text("\(displayedSpeed)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.default, value: displayedSpeed)
                    Gauge(value: animatedSpeed.wrappedValue, in: 0...180) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinear)
                    .tint(.white)
                    .frame(width: geometry.size.width * 0.3)
                    Text("mph")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 50, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .offset(y: -1)
                }
                .padding(.horizontal, 5)
            }
            .onAppear {
                animatedSpeed.wrappedValue = locationHandler.speedMPH
            }
        }
        
        @ViewBuilder
        func trackList() -> some View {
            let displayTracks = pendingSoundtrack?.tracks ?? audioController.currentTracks
            let displayedTitle = pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle
            VStack(spacing: 10) {
                if !displayTracks.isEmpty && displayTracks[0].audioFileName.contains("Base") {
                    GeometryReader { geometry in
                        ZStack {
                            Color.black.opacity(0.3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                )
                                .frame(width: geometry.size.width, height: 108)
                                .cornerRadius(16)
                            HStack(alignment: .center, spacing: 0) {
                                Text(displayTracks[0].displayName)
                                    .font(.system(size: 35, weight: .semibold))
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                    .minimumScaleFactor(0.3)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .foregroundColor(.white)
                                    .padding(.leading, 16)
                                WaveformView(isPlaying: audioController.isSoundtrackPlaying, currentSoundtrackTitle: displayedTitle)
                                    .frame(width: 70, height: 50)
                                    .padding(.trailing, 16)
                            }
                        }
                    }
                    .frame(height: 108)
                }
                if displayTracks.count > 1 {
                    ForEach(1..<displayTracks.count, id: \.self) { index in
                        GeometryReader { geometry in
                            ZStack {
                                Color.black.opacity(0.3)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                    )
                                    .frame(width: geometry.size.width, height: 108)
                                    .cornerRadius(16)
                                if displayTracks[index].minimumSpeed == 0 && displayTracks[index].maximumSpeed == 0 {
                                    HStack(alignment: .center, spacing: 0) {
                                        Text(displayTracks[index].displayName)
                                            .font(.system(size: 35, weight: .semibold))
                                            .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                            .minimumScaleFactor(0.3)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)
                                            .foregroundColor(.white)
                                            .padding(.leading, 16)
                                        WaveformView(isPlaying: audioController.isSoundtrackPlaying, currentSoundtrackTitle: displayedTitle)
                                            .frame(width: 70, height: 50)
                                            .padding(.trailing, 16)
                                    }
                                } else {
                                    ZStack(alignment: .topLeading) {
                                        VStack(spacing: 4) {
                                            Text(displayTracks[index].displayName)
                                                .font(.system(size: 35, weight: .semibold))
                                                .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                                                .minimumScaleFactor(0.3)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(2)
                                                .foregroundColor(.white)
                                                .padding(.leading, 16)
                                                .padding(.top, 3)
                                                .offset(x: -41, y: 12)
                                            HStack(spacing: 8) {
                                                Text("\(displayTracks[index].minimumSpeed)")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.5))
                                                    .scaleEffect(minSpeedScale[index] ?? 1.0)
                                                Gauge(value: Double(audioController.calculateVolumeForTrack(at: index, speed: locationHandler.speedMPH)),
                                                      in: 0...Double(mapVolume(displayTracks[index].maximumVolume))) {
                                                    EmptyView()
                                                }
                                                .gaugeStyle(.linearCapacity)
                                                .tint(.gray)
                                                .frame(width: geometry.size.width * 0.75, height: 10)
                                                .animation(.easeInOut(duration: 1.0), value: locationHandler.speedMPH)
                                                Text("\(displayTracks[index].maximumSpeed)")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.5))
                                                    .scaleEffect(maxSpeedScale[index] ?? 1.0)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .offset(y: 20)
                                        }
                                        WaveformView(isPlaying: audioController.isSoundtrackPlaying, currentSoundtrackTitle: displayedTitle)
                                            .frame(width: 70, height: 50)
                                            .padding(.trailing, 16)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                            .offset(y: 14)
                                    }
                                }
                            }
                            .frame(height: 108)
                        }
                    }
                }
            }
        }
        
        @ViewBuilder
        func playbackButtons() -> some View {
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showPlaybackPage = false
                            shouldResetPlaybackPage = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            pendingSoundtrack = nil
                            shouldResetPlaybackPage = false
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .overlay(
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            audioController.masterPlaybackTime = 0
                            for player in audioController.currentPlayers {
                                player?.currentTime = 0
                            }
                            audioController.updateNowPlayingInfo()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isRewindShowingCheckmark = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isRewindShowingCheckmark = false
                                }
                            }
                        }) {
                            Image(systemName: isRewindShowingCheckmark ? "checkmark" : "backward.end.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .opacity(audioController.isSoundtrackPlaying ? 0 : 1)
                        .offset(x: 60)
                    )
                    
                    Button(action: {
                        if let pending = pendingSoundtrack, audioController.currentSoundtrackTitle != pending.title {
                            if audioController.isSoundtrackPlaying {
                                audioController.toggleSoundtrackPlayback()
                            }
                            audioController.setCurrentSoundtrack(tracks: pending.tracks, players: pending.players, title: pending.title)
                            audioController.toggleSoundtrackPlayback()
                        } else {
                            audioController.toggleSoundtrackPlayback()
                        }
                    }) {
                        Image(systemName: audioController.isSoundtrackPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .frame(width: 70, height: 70)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showEditPage = true
                        }
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .popoverTip(editTip, arrowEdge: .top)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
        
        return VStack(spacing: 10) {
            HStack {
                Text(pendingSoundtrack?.title ?? audioController.currentSoundtrackTitle)
                    .font(.system(size: 35, weight: .medium))
                    .foregroundColor(.white)
                    .offset(y: -15)
                Spacer()
            }
            GeometryReader { geometry in
                speedGauge(geometry: geometry, displayedSpeed: displayedSpeed, animatedSpeed: $animatedSpeed)
            }
            .frame(height: 50)
            .offset(y: -25)
            trackList()
            .offset(y: -20)
            Spacer()
        }
        .padding()
        .overlay(playbackButtons())
        .zIndex(4)
    }
    
    // MARK: - Edit Page
    private var editPage: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Edit Soundtrack")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            Spacer()
        }
        .padding()
        .overlay(
            Button(action: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showEditPage = false
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding()
        )
        .zIndex(4)
    }
  
    // MARK: Speed Detail Components
    private func landscapeLinearGauge(geometry: GeometryProxy) -> some View {
        let scaledSpeed = min(animatedSpeed, 100)
        return ZStack(alignment: .center) {
            // Soundtrack title for linear gauge only
            if landscapeShowSoundtrackTitle {
                Text(pendingSoundtrack?.title ?? (audioController.currentSoundtrackTitle.isEmpty ? " " : audioController.currentSoundtrackTitle))
                    .font(.system(size: 45, weight: .bold, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: landscapeShowMinMax ? .center : .leading)
                    .padding(.bottom, 20)
                    .offset(x: landscapeShowMinMax ? 0 : 80, y: -40)
            }
            
            // Linear gauge
            Group {
                if landscapeIndicatorStyle == "fill" {
                    if landscapeShowMinMax {
                        Gauge(value: scaledSpeed, in: 0...100) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("0")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        } maximumValueLabel: {
                            Text("100")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .frame(width: geometry.size.width * 0.2, height: 8)
                        .scaleEffect(4.0)
                    } else {
                        Gauge(value: scaledSpeed, in: 0...100) {
                            EmptyView()
                        }
                        .gaugeStyle(.linearCapacity)
                        .frame(width: geometry.size.width * 0.2, height: 8)
                        .scaleEffect(4.0)
                    }
                } else {
                    Gauge(value: scaledSpeed, in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        if landscapeShowMinMax {
                            Text("0")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        }
                    } maximumValueLabel: {
                        if landscapeShowMinMax {
                            Text("100")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        }
                    }
                    .gaugeStyle(.accessoryLinear)
                    .frame(width: geometry.size.width * 0.2, height: 100)
                    .scaleEffect(4.0)
                }
            }
            .tint(.white)
            
            // Speed value for linear gauge only
            if landscapeShowCurrentSpeed {
                if landscapeShowMinMax == false {
                    Text("\(Int(animatedSpeed)) mph")
                        .font(.system(size: 40, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white.opacity(0.5))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: false))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                        .offset(x:80, y: 40)
                }; if landscapeShowMinMax == true {
                    Text("\(Int(animatedSpeed)) mph")
                        .font(.system(size: 40, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white.opacity(0.5))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: false))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                        .offset(y: 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func landscapeCircularGauge(geometry: GeometryProxy) -> some View {
        let scaledSpeed = min(animatedSpeed, 100)
        return ZStack {
            Gauge(value: scaledSpeed, in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            } minimumValueLabel: {
                if landscapeShowMinMax {
                    Text("0")
                        .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
            } maximumValueLabel: {
                if landscapeShowMinMax {
                    Text("100")
                        .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.white.opacity(1))
            .frame(width: min(geometry.size.width, geometry.size.height) * 0.7)
            .scaleEffect(4.5)
            
            if landscapeShowCurrentSpeed {
                Text("\(Int(animatedSpeed))")
                    .font(.system(size: 110, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .offset(y: -5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    
    private func portraitGauge(geometry: GeometryProxy) -> some View {
        let scaledSpeed = min(animatedSpeed, 100)
        return Group {
            if portraitGaugeStyle == "fullCircle" {
                ZStack {
                    Gauge(value: scaledSpeed, in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        EmptyView()
                    } maximumValueLabel: {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.white.opacity(0.5))
                    .frame(width: geometry.size.width * 0.7, height: geometry.size.width * 0.7)
                    .scaleEffect(5.0)
                    
                    if showPortraitSpeed {
                        Text("\(Int(animatedSpeed))")
                            .font(.system(size: 110, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
            } else {
                ZStack {
                    Gauge(value: scaledSpeed, in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        if portraitShowMinMax {
                            Text("0")
                                .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                    } maximumValueLabel: {
                        if portraitShowMinMax {
                            Text("100")
                                .font(.system(size: 10, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(.white.opacity(1))
                    .frame(width: geometry.size.width * 0.7, height: geometry.size.width * 0.7)
                    .scaleEffect(5.0)
                    
                    if showPortraitSpeed {
                        Text("\(Int(animatedSpeed))")
                            .font(.system(size: 110, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                            .offset(y: -5)
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Speed Detail
    private var speedDetailPage: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            ZStack {
                // Black background if enabled
                if useBlackBackground {
                    Rectangle()
                        .fill(.black)
                        .ignoresSafeArea()
                }
                
                // Main content (gauge)
                VStack {
                    Spacer()
                    
                    if isLandscape {
                        if landscapeGaugeStyle == "line" {
                            landscapeLinearGauge(geometry: geometry)
                        } else {
                            landscapeCircularGauge(geometry: geometry)
                        }
                    } else {
                        portraitGauge(geometry: geometry)
                    }
                    
                    Spacer()
                }
                .animation(.easeInOut(duration: 1.0), value: animatedSpeed)

                // Bottom buttons
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showSpeedDetailPage = false
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showSettingsPage = true
                            }
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, 20)
                    .opacity(areButtonsVisible ? 1 : 0)
                    .animation(areButtonsVisible ? .easeInOut(duration: 0.3) : .easeInOut(duration: 0.5), value: areButtonsVisible)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture()
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            areButtonsVisible = true
                        }
                        startInactivityTimer()
                    }
            )
            .onAppear {
                setDeviceOrientation(.allButUpsideDown)
                areButtonsVisible = true
                startInactivityTimer()
                UIApplication.shared.isStatusBarHidden = true
            }
            .onDisappear {
                setDeviceOrientation(.portrait)
                areButtonsVisible = true
                invalidateInactivityTimer()
                UIApplication.shared.isStatusBarHidden = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                deviceOrientation = UIDevice.current.orientation
            }
            .zIndex(4)
        }
        .ignoresSafeArea()
    }
    

    private func startInactivityTimer() {
        invalidateInactivityTimer()
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                withAnimation {
                    areButtonsVisible = false
                }
            }
        }
    }

    private func invalidateInactivityTimer() {
    }
    
    // MARK: Settings
    private var settingsPage: some View {
        ZStack {
            // Background content
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text("Settings")
                            .font(.system(size: 35, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    
                    // Portrait Gauge Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Portrait Gauge")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Picker("Gauge Style", selection: $portraitGaugeStyle) {
                            Text("Full Circle").tag("fullCircle")
                            Text("Separated Arc").tag("separatedArc")
                        }
                        .pickerStyle(.segmented)
                        
                        if portraitGaugeStyle == "separatedArc" {
                            Toggle("Show Min/Max Values", isOn: Binding(
                                get: { portraitShowMinMax },
                                set: { newValue in
                                    portraitShowMinMax = newValue
                                    if syncCircularGaugeSettings && landscapeGaugeStyle == "circular" {
                                        landscapeShowMinMax = newValue
                                    }
                                }
                            ))
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        }
                        
                        Toggle("Show Current Speed", isOn: Binding(
                            get: { showPortraitSpeed },
                            set: { newValue in
                                showPortraitSpeed = newValue
                                if syncCircularGaugeSettings && landscapeGaugeStyle == "circular" {
                                    landscapeShowCurrentSpeed = newValue
                                }
                            }
                        ))
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    
                    // Landscape Gauge Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Landscape Gauge")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Picker("Gauge Style", selection: Binding(
                            get: { landscapeGaugeStyle },
                            set: { newValue in
                                landscapeGaugeStyle = newValue
                                if newValue == "circular" && syncCircularGaugeSettings {
                                    // Sync portrait settings to landscape when switching to circular
                                    landscapeShowMinMax = portraitShowMinMax
                                    landscapeShowCurrentSpeed = showPortraitSpeed
                                }
                            }
                        )) {
                            Text("Line").tag("line")
                            Text("Circular").tag("circular")
                        }
                        .pickerStyle(.segmented)
                        
                        if landscapeGaugeStyle == "line" {
                            Picker("Indicator Style", selection: $landscapeIndicatorStyle) {
                                Text("Dot").tag("line")
                                Text("Fill").tag("fill")
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        Toggle("Show Min/Max Values", isOn: Binding(
                            get: { landscapeShowMinMax },
                            set: { newValue in
                                landscapeShowMinMax = newValue
                                if syncCircularGaugeSettings && landscapeGaugeStyle == "circular" {
                                    portraitShowMinMax = newValue
                                }
                            }
                        ))
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        
                        Toggle("Show Current Speed", isOn: Binding(
                            get: { landscapeShowCurrentSpeed },
                            set: { newValue in
                                landscapeShowCurrentSpeed = newValue
                                if syncCircularGaugeSettings && landscapeGaugeStyle == "circular" {
                                    showPortraitSpeed = newValue
                                }
                            }
                        ))
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        
                        if landscapeGaugeStyle == "line" {
                            Toggle("Show Soundtrack Title", isOn: $landscapeShowSoundtrackTitle)
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                        }
                        
                        if landscapeGaugeStyle == "circular" {
                            Toggle("Sync with Portrait Settings", isOn: Binding(
                                get: { syncCircularGaugeSettings },
                                set: { newValue in
                                    syncCircularGaugeSettings = newValue
                                    if newValue {
                                        // When enabling sync, copy portrait settings to landscape
                                        landscapeShowMinMax = portraitShowMinMax
                                        landscapeShowCurrentSpeed = showPortraitSpeed
                                    }
                                }
                            ))
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    
                    // General Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("General")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Toggle("Use Black Background", isOn: $useBlackBackground)
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        
                        Picker("Gauge Font Style", selection: $gaugeFontStyle) {
                            Text("Default").tag("default")
                            Text("Rounded").tag("rounded")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding()
            }

            // Empty stack between content and buttons
            ZStack {
            }
            .frame(height: 150)
            .allowsHitTesting(false)
            .glur(radius: 8.0,
                  offset: 0.3,
                  interpolation: 0.4,
                  direction: .down)

            // Fixed bottom controls
            VStack {
                Spacer()
                HStack(spacing: 80) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showSettingsPage = false
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
        .zIndex(5)
    }
    
    
    // MARK: - Info Page
    private func infoPage() -> some View {
        infoPageBackground
            .overlay(infoPageContent)
    }
    
    private var infoPageBackground: some View {
        Color(red: 26/255, green: 20/255, blue: 26/255)
            .edgesIgnoringSafeArea(.all)
    }
    
    private var infoPageContent: some View {
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
    }
    
    // MARK: - Persistence Functions
    private func saveSoundtracks() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to access documents directory for saving soundtracks")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("soundtracks.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(soundtracks)
            try data.write(to: fileURL, options: .atomic)
            print("Saved soundtracks to \(fileURL.path)")
        } catch {
            print("Failed to save soundtracks: \(error)")
        }
    }
    
    private func loadSoundtracks() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to access documents directory for loading soundtracks")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("soundtracks.json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("No saved soundtracks found at \(fileURL.path)")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            var loadedSoundtracks = try decoder.decode([Soundtrack].self, from: data)
            
            // Recreate players for each soundtrack
            for i in 0..<loadedSoundtracks.count {
                let tracks = loadedSoundtracks[i].tracks
                let players: [AVAudioPlayer?] = tracks.map { track -> AVAudioPlayer? in
                    let audioURL = documentsDirectory.appendingPathComponent(track.audioFileName)
                    do {
                        let player = try AVAudioPlayer(contentsOf: audioURL)
                        player.volume = mapVolume(track.maximumVolume)
                        return player
                    } catch {
                        print("Failed to create AVAudioPlayer for \(track.audioFileName): \(error)")
                        return nil
                    }
                }
                loadedSoundtracks[i] = Soundtrack(id: loadedSoundtracks[i].id,
                                                  title: loadedSoundtracks[i].title,
                                                  tracks: tracks,
                                                  players: players)
            }
            
            soundtracks = loadedSoundtracks
            print("Loaded \(soundtracks.count) soundtracks from \(fileURL.path)")
        } catch {
            print("Failed to load soundtracks: \(error)")
        }
    }
    
    // MARK: - Helper Functions
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
        stopPreviewTrackingTimer()
    }
    
    private func toggleBasePlayback() {
        guard let player = createBasePlayer else { return }
        if createBaseIsPlaying {
            player.pause()
            createBaseIsPlaying = false
            if !createAdditionalZStacks.contains(where: { $0.isPlaying }) {
                audioController.masterPlaybackTime = player.currentTime
                stopPreviewTrackingTimer()
            }
        } else {
            if let firstPlayingPlayer = getFirstPlayingPlayer(), firstPlayingPlayer.isPlaying {
                audioController.masterPlaybackTime = firstPlayingPlayer.currentTime
            }
            player.currentTime = audioController.masterPlaybackTime
            player.play()
            createBaseIsPlaying = true
            startPreviewTrackingTimer()
        }
    }
    
    private func togglePlayback(at index: Int) {
        guard let player = createAdditionalZStacks[index].player else { return }
        if createAdditionalZStacks[index].isPlaying {
            player.pause()
            createAdditionalZStacks[index].isPlaying = false
            if !createBaseIsPlaying && !createAdditionalZStacks.contains(where: { $0.isPlaying && $0.id != createAdditionalZStacks[index].id }) {
                audioController.masterPlaybackTime = player.currentTime
                stopPreviewTrackingTimer()
            }
        } else {
            if let firstPlayingPlayer = getFirstPlayingPlayer(), firstPlayingPlayer.isPlaying {
                audioController.masterPlaybackTime = firstPlayingPlayer.currentTime
            }
            player.currentTime = audioController.masterPlaybackTime
            player.play()
            createAdditionalZStacks[index].isPlaying = true
            startPreviewTrackingTimer()
        }
    }
    
    private func startPreviewTrackingTimer() {
        if previewTrackingTimer == nil && (createBaseIsPlaying || createAdditionalZStacks.contains(where: { $0.isPlaying })) {
            previewTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
                if let firstPlayingPlayer = getFirstPlayingPlayer(), firstPlayingPlayer.isPlaying {
                    audioController.masterPlaybackTime = firstPlayingPlayer.currentTime
                }
            }
        }
    }
    
    private func stopPreviewTrackingTimer() {
        previewTrackingTimer?.invalidate()
        previewTrackingTimer = nil
    }
    
    private func getFirstPlayingPlayer() -> AVAudioPlayer? {
        if createBaseIsPlaying, let basePlayer = createBasePlayer, basePlayer.isPlaying {
            return basePlayer
        }
        for index in createAdditionalZStacks.indices {
            if createAdditionalZStacks[index].isPlaying, let player = createAdditionalZStacks[index].player, player.isPlaying {
                return player
            }
        }
        return nil
    }
    
    private func mapVolume(_ percentage: Float) -> Float {
        let mapped = (percentage + 100) / 100
        return max(0.0, min(2.0, mapped))
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
    
    private func resetCreatePage() {
        createBaseAudioURL = nil
        createBasePlayer = nil
        createBaseIsPlaying = false
        createBaseOffset = 0
        createBaseShowingFilePicker = false
        createBaseVolume = 0.0
        createBaseTitle = "Base"
        createAdditionalZStacks.removeAll()
        createAdditionalTitles.removeAll()
        createAdditionalAlwaysPlaying.removeAll()
        createSoundtrackTitle = "New Soundtrack"
        createReferenceLength = nil
        createNextID = 1
        createAudio1MinimumSpeed = 0
        createAudio1MaximumSpeed = 80
        createAudio2MinimumSpeed = 0
        createAudio2MaximumSpeed = 80
        createAudio3MinimumSpeed = 0
        createAudio3MaximumSpeed = 80
        createAudio4MinimumSpeed = 0
        createAudio4MaximumSpeed = 80
        createAudio5MinimumSpeed = 0
        createAudio5MaximumSpeed = 80
    }
    
    private func deleteSoundtrack(_ soundtrack: Soundtrack) {
        // Ensure there is at least one track before attempting to access it
        guard let firstTrack = soundtrack.tracks.first else {
            print("No tracks found for soundtrack: \(soundtrack.title)")
            soundtracks.removeAll { $0.id == soundtrack.id }
            if audioController.currentSoundtrackTitle == soundtrack.title {
                audioController.setCurrentSoundtrack(tracks: [], players: [], title: "")
            }
            saveSoundtracks()
            return
        }
        
        let audioURL = documentsDirectory.appendingPathComponent(firstTrack.audioFileName)
        removeAudioFile(at: audioURL)
        
        soundtracks.removeAll { $0.id == soundtrack.id }
        
        if audioController.currentSoundtrackTitle == soundtrack.title {
            audioController.setCurrentSoundtrack(tracks: [], players: [], title: "")
        }
        
        print("Deleted soundtrack: \(soundtrack.title)")
        saveSoundtracks() // Save the updated soundtracks
    }
    
    private func handleDoneAction() {
        let successHaptic = UINotificationFeedbackGenerator()
        successHaptic.notificationOccurred(.success)
        var tracks: [AudioController.SoundtrackData] = []
        
        if let baseURL = createBaseAudioURL {
            tracks.append(AudioController.SoundtrackData(
                audioFileName: baseURL.lastPathComponent,
                displayName: createBaseTitle,
                maximumVolume: createBaseVolume,
                minimumSpeed: 0,
                maximumSpeed: 0
            ))
        }
        
        for (index, zStack) in createAdditionalZStacks.enumerated() {
            if let audioURL = zStack.audioURL {
                let minSpeed: Int
                let maxSpeed: Int
                switch index {
                case 0:
                    minSpeed = createAudio1MinimumSpeed
                    maxSpeed = createAudio1MaximumSpeed
                case 1:
                    minSpeed = createAudio2MinimumSpeed
                    maxSpeed = createAudio2MaximumSpeed
                case 2:
                    minSpeed = createAudio3MinimumSpeed
                    maxSpeed = createAudio3MaximumSpeed
                case 3:
                    minSpeed = createAudio4MinimumSpeed
                    maxSpeed = createAudio4MaximumSpeed
                case 4:
                    minSpeed = createAudio5MinimumSpeed
                    maxSpeed = createAudio5MaximumSpeed
                default:
                    minSpeed = 0
                    maxSpeed = 80
                }
                tracks.append(AudioController.SoundtrackData(
                    audioFileName: audioURL.lastPathComponent,
                    displayName: index < createAdditionalTitles.count ? createAdditionalTitles[index] : "Audio \(index + 1)",
                    maximumVolume: zStack.volume,
                    minimumSpeed: minSpeed,
                    maximumSpeed: maxSpeed
                ))
            }
        }
        
        let players = tracks.map { track in
            let fileManager = FileManager.default
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("Failed to access documents directory")
                return nil as AVAudioPlayer?
            }
            let audioURL = documentsDirectory.appendingPathComponent(track.audioFileName)
            do {
                let player = try AVAudioPlayer(contentsOf: audioURL)
                player.volume = mapVolume(track.maximumVolume)
                player.prepareToPlay()
                return player
            } catch {
                print("Failed to create AVAudioPlayer for \(track.audioFileName): \(error)")
                return nil as AVAudioPlayer?
            }
        }
        
        // Handle duplicate titles before appending the new soundtrack
        var newTitle = createSoundtrackTitle.trimmingCharacters(in: .whitespaces)
        var titleCount = 2
        while soundtracks.contains(where: { $0.title == newTitle }) {
            newTitle = "\(createSoundtrackTitle.trimmingCharacters(in: .whitespaces)) \(titleCount)"
            titleCount += 1
        }
        
        // Append the new soundtrack with the unique title
        soundtracks.append(Soundtrack(id: UUID(), title: newTitle, tracks: tracks, players: players))
        pauseAllAudio()
        
        // Navigate back to mainScreen
        withAnimation(.easeInOut(duration: 0.5)) {
            showConfigurePage = false
            showCreatePage = false
        }
        
        // Delay the reset of createPage/configurePage state by 1.5 seconds (0.5s animation + 1s extra)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            resetCreatePage()
            print("Delayed resetCreatePage() called after 1.5 seconds")
        }
        
        print("Done pressed: Added new soundtrack: \(newTitle)")
        saveSoundtracks() // Save the updated soundtracks
    }
}

private func setDeviceOrientation(_ orientation: UIInterfaceOrientationMask) {
    // Get the window scene
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
        print("Failed to get window scene for orientation change")
        return
    }
    
    // Request orientation update
    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
        print("Failed to update orientation: \(error)")
    }
}

// MARK: - Custom Views
struct WaveformView: View {
    let isPlaying: Bool
    let currentSoundtrackTitle: String // Add this to compare with the playing soundtrack
    @EnvironmentObject private var audioController: AudioController // Access AudioController
    @State private var heights: [CGFloat] = Array(repeating: 15, count: 6)
    
    private let barWidth: CGFloat = 7
    private let spacing: CGFloat = 3
    private let cornerRadius: CGFloat = 4.5
    
    private var shouldAnimate: Bool {
        isPlaying && audioController.currentSoundtrackTitle == currentSoundtrackTitle
    }
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<heights.count, id: \.self) { index in
                if shouldAnimate {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: barWidth, height: heights[index])
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                } else {
                    Circle()
                        .frame(width: barWidth, height: barWidth)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
            }
        }
        .frame(width: 70, height: 50, alignment: .center)
        .background(Color.clear)
        .clipped()
        .onAppear {
            if shouldAnimate {
                startAnimating()
            }
        }
        .onChange(of: shouldAnimate) { oldValue, newValue in
            if newValue {
                startAnimating()
            } else {
                heights = Array(repeating: 15, count: heights.count)
            }
        }
    }
    
    private func startAnimating() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            guard shouldAnimate else { timer.invalidate(); return }
            heights = (0..<heights.count).map { index in
                let centerBias = abs(Double(index - (heights.count - 1) / 2)) / Double(heights.count / 2)
                let baseHeight = CGFloat.random(in: 5...40)
                let reducedHeight = baseHeight * (1 - (centerBias * 0.6))
                return max(5, min(40, reducedHeight))
            }
        }
    }
}

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .regular
    var intensity: CGFloat = 1.0
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.alpha = intensity
    }
}

enum BlurDirection {
    case blurredBottomClearTop
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.mp3], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onPick(url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

// MARK: - Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - LocationHandler
class LocationHandler: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var speedMPH: Double = 0.0
    @Published var status: String = "Starting..."
    @Published var location: CLLocation?
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    func startLocationUpdates() {
        let authStatus = locationManager.authorizationStatus
        print("Location authorization status on start: \(authStatus)")
        if authStatus == .notDetermined {
            print("Requesting Always authorization")
            locationManager.requestAlwaysAuthorization()
            status = "Requesting permission..."
        } else if authStatus == .denied || authStatus == .restricted {
            status = "Location access denied - check Settings"
            print("Location access denied or restricted")
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
            locationManager.activityType = .automotiveNavigation
            locationManager.startUpdatingLocation()
            status = "Waiting for GPS fix..."
            print("Started location updates with desired accuracy: BestForNavigation")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            speedMPH = 0.0
            status = "No location data"
            print("No location data received")
            return
        }
        self.location = location
        let speed = max(location.speed, 0)
        speedMPH = min(speed * 2.23694, 80)
        status = "Lat: \(location.coordinate.latitude), Lon: \(location.coordinate.longitude), Speed: \(String(format: "%.1f", speedMPH)) mph"
        print("Location update: Speed = \(String(format: "%.1f", speedMPH)) mph, Status = \(status)")
        
        if let audioController = (UIApplication.shared.delegate as? AppDelegate)?.audioController {
            audioController.adjustVolumesForSpeed(speedMPH)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Error: \(error.localizedDescription)"
        speedMPH = 0.0
        location = nil
        print("Location update failed: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Authorization status changed to: \(status)")
        switch status {
        case .notDetermined:
            self.status = "Awaiting permission"
        case .restricted, .denied:
            self.status = "Location access denied - check Settings"
            print("Location access denied or restricted")
        case .authorizedWhenInUse:
            print("Received When In Use, requesting Always authorization")
            locationManager.requestAlwaysAuthorization()
            self.status = "Requesting Always permission..."
        case .authorizedAlways:
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
            locationManager.activityType = .automotiveNavigation
            locationManager.startUpdatingLocation()
            self.status = "Waiting for GPS fix..."
            print("Started location updates with Always authorization")
        @unknown default:
            self.status = "Unknown authorization status"
            print("Unknown authorization status")
        }
    }
}

#Preview {
    ContentView()
}

