import SwiftUI
import CoreLocation
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import MediaPlayer
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
            locationHandler.stopDistanceTracking()
            updateSyncTimer()
        } else {
            let deviceCurrentTime = currentPlayers.first(where: { $0 != nil })??.deviceCurrentTime ?? 0
            let startTime = deviceCurrentTime + 0.1
            
            locationHandler.startDistanceTracking()
            
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
                locationHandler.stopDistanceTracking()
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
    @State private var showSpeedDetailPage = false
    @State private var showShareSheet = false
    @State private var showImportPage = false // New state for import page
    @State private var showImportPicker = false // New state for import picker
    @State private var importedSoundtrackURL: URL? // Store imported soundtrack folder URL
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
    @AppStorage("mapStyle") private var mapStyle: MapStyle = .standard
    @AppStorage("backgroundType") private var backgroundType: BackgroundType = .map
    
    // Gradient Start Color Components
    @AppStorage("gradientStartRed") private var gradientStartRed: Double = 0
    @AppStorage("gradientStartGreen") private var gradientStartGreen: Double = 122/255
    @AppStorage("gradientStartBlue") private var gradientStartBlue: Double = 1.0
    
    // Gradient End Color Components
    @AppStorage("gradientEndRed") private var gradientEndRed: Double = 88/255
    @AppStorage("gradientEndGreen") private var gradientEndGreen: Double = 86/255
    @AppStorage("gradientEndBlue") private var gradientEndBlue: Double = 214/255
    
    // Computed properties for gradient colors
    private var gradientStartColor: Color {
        Color(red: gradientStartRed, green: gradientStartGreen, blue: gradientStartBlue)
    }
    
    private var gradientEndColor: Color {
        Color(red: gradientEndRed, green: gradientEndGreen, blue: gradientEndBlue)
    }
    
    enum MapStyle: String {
        case standard
        case satellite
    }
    
    enum BackgroundType: String, Codable {
        case map
        case gradient
    }
    
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
    @State private var animateCards: Bool = false // Start invisible
    @State private var hasAnimatedOnce: Bool = false
    
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
    @State private var showAIUploadPage: Bool = false // New state for AI Upload page
    
    @State private var currentPage: AppPage = .loading
    @State private var previousPage: AppPage? = nil
    
    
    private var documentsDirectory: URL {
        let fileManager = FileManager.default
        guard let baseDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Failed to access documents directory")
        }
        
        // Create a hidden directory for soundtrack files
        let hiddenDirectory = baseDirectory.appendingPathComponent(".dynamidrive_data")
        
        // Create the directory if it doesn't exist
        if !fileManager.fileExists(atPath: hiddenDirectory.path) {
            do {
                try fileManager.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true, attributes: nil)
                
                // Add a .nomedia file to hide media from gallery apps (Android convention, but doesn't hurt)
                let nomediaPath = hiddenDirectory.appendingPathComponent(".nomedia")
                if !fileManager.fileExists(atPath: nomediaPath.path) {
                    fileManager.createFile(atPath: nomediaPath.path, contents: nil)
                }
            } catch {
                print("Error creating hidden directory: \(error)")
            }
        }
        
        return hiddenDirectory
    }
    
    // MARK: Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Fixed map and blur background for all pages
                if backgroundType == .map {
                    Map(position: $cameraPosition, interactionModes: []) {
                        UserAnnotation()
                    }
                    .mapStyle(mapStyle == .satellite ? .imagery(elevation: .realistic) : .standard)
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
                } else {
                    LinearGradient(
                        gradient: Gradient(colors: [gradientStartColor, gradientEndColor]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(.all)
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
                                .transition(.asymmetric(
                                    insertion: previousPage == .masterSettings ? .move(edge: .leading) : (previousPage == .import ? .move(edge: .trailing) : (isReturningFromConfigure ? .move(edge: .trailing) : (previousPage == .create || previousPage == .playback ? .move(edge: .leading) : .move(edge: .trailing)))),
                                    removal: .move(edge: .leading)))
                        case .create:
                            createScreen
                                .transition(.asymmetric(
                                    insertion: previousPage == .import ? .move(edge: .leading) : .move(edge: createPageInsertionDirection),
                                    removal: .move(edge: createPageRemovalDirection)))
                        case .configure:
                            configureScreen
                                .transition(.asymmetric(insertion: .move(edge: configurePageInsertionDirection), removal: .move(edge: configurePageRemovalDirection)))
                        case .volume:
                            volumeScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: volumePageRemovalDirection)))
                        case .playback:
                            EmptyView() // Remove the direct view presentation since we'll use a sheet
                        case .edit:
                            editScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                        case .speedDetail:
                            speedDetailScreen
                                .transition(.asymmetric(
                                    insertion: previousPage == .playback ? .move(edge: .trailing) : .move(edge: .leading),
                                    removal: showSettingsPage ? .move(edge: .leading) : .move(edge: .trailing)
                                ))
                        case .settings:
                            settingsScreen
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing),
                                    removal: .move(edge: .trailing)
                                ))
                        case .import:
                            importScreen
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing),
                                    removal: currentPage == .create ? .move(edge: .trailing) : .move(edge: .leading)
                                ))
                        case .aiUpload:
                            aiUploadScreen
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing),
                                    removal: currentPage == .import ? .move(edge: .trailing) : .move(edge: .leading)
                                ))
                        case .masterSettings:
                            MasterSettings(currentPage: $currentPage)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing),
                                    removal: .move(edge: .trailing)
                                ))
                        }
                    }
                    .zIndex(9) // Current page is on top
                }
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
                    
                    // Start card animations after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            animateCards = true
                        }
                    }
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
            if !newValue {
                // When closing the playback sheet, return to the previous page
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentPage = previousPage == .volume ? .volume : .main
                }
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
            
            // Handle masterSettings page transition
            if newPage == .masterSettings {
                withAnimation(.easeInOut(duration: 0.5)) {
                    previousPage = oldPage
                }
            } else if newPage == .main && oldPage == .masterSettings {
                withAnimation(.easeInOut(duration: 0.5)) {
                    previousPage = .masterSettings
                    // Force main to slide in from left
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentPage = .main
                        }
                    }
                }
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
        .sheet(isPresented: $showPlaybackPage) {
            PlaybackPage(
                showPlaybackPage: $showPlaybackPage,
                pendingSoundtrack: $pendingSoundtrack,
                showEditPage: $showEditPage,
                showSpeedDetailPage: $showSpeedDetailPage,
                isRewindShowingCheckmark: $isRewindShowingCheckmark
            )
            .environmentObject(locationHandler)
            .presentationDetents([.height(100), .height(200), .large], selection: .constant(.height(200)))
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
    }
    
    
    // MARK: Main Page
    private var mainScreen: some View {
        MainScreen(
            currentPage: $currentPage,
            showCreatePage: $showCreatePage,
            showImportPage: $showImportPage,
            importedSoundtrackURL: $importedSoundtrackURL,
            showPlaybackPage: $showPlaybackPage,
            pendingSoundtrack: $pendingSoundtrack,
            soundtracks: $soundtracks,
            animateCards: $animateCards,
            hasAnimatedOnce: $hasAnimatedOnce,
            isMainScreenEditMode: $isMainScreenEditMode,
            soundtracksBeingDeleted: $soundtracksBeingDeleted,
            previousPage: $previousPage,
            resetCreatePage: resetCreatePage,
            deleteSoundtrack: deleteSoundtrack
        )
        .environmentObject(locationHandler)
    }
    
    // MARK: - Loading Screen
    private var loadingScreen: some View {
        LoadingScreen(isLoading: $isLoading, isSpinning: $isSpinning, currentPage: $currentPage)
    }
    
    // MARK: - Create Page
        private var createScreen: some View {
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
                                .glassEffect(.regular.tint(.clear).interactive())                        }
                        
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
                                .glassEffect(.regular.tint(.clear).interactive())
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
                                    gradientRotation = 0 // Reset rotation
                                    withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                                        gradientRotation = 360
                                    }
                                }
                                .onDisappear {
                                    gradientRotation = 0 // Reset rotation when view disappears
                                }
                            
                            Button(action: {
                                showAIUploadPage = true
                                currentPage = .aiUpload
                                previousPage = .create
                            }) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .glassEffect(.regular.tint(.clear).interactive())
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
                Rectangle()
                    .fill(.clear)
                    .background(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.4))
                    .frame(width: geometry.size.width, height: 108)
                    .cornerRadius(16)
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
                Rectangle()
                    .fill(.clear)
                    .background(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.4))
                    .frame(width: geometry.size.width, height: 108)
                    .cornerRadius(16)
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
            HStack(spacing: 20) {
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
                        .glassEffect(.regular.tint(.clear).interactive())
                }
                
            }
            .padding(.top, 10)
        }
    
    // MARK: - Volume Page
    private var volumeScreen: some View {
        VolumeScreen( 
            showVolumePage: $showVolumePage,
            createBaseTitle: $createBaseTitle,
            createBaseVolume: Binding(
                get: { Double(createBaseVolume) },  // Convert Float to Double for VolumeScreen
                set: { createBaseVolume = Float($0) }  // Convert Double back to Float
            ),
            createBaseAudioURL: $createBaseAudioURL,
            createBasePlayer: $createBasePlayer,
            createAdditionalZStacks: $createAdditionalZStacks,
            createAdditionalTitles: $createAdditionalTitles
        )
    }
    
    // MARK: Configure Page
    private var configureScreen: some View {
        ConfigurePage(
            showConfigurePage: $showConfigurePage,
            showCreatePage: $showCreatePage,
            showVolumePage: $showVolumePage,
            createBaseAudioURL: $createBaseAudioURL,
            createAdditionalZStacks: $createAdditionalZStacks,
            createAdditionalTitles: $createAdditionalTitles,
            createAdditionalAlwaysPlaying: $createAdditionalAlwaysPlaying,
            createAudio1MinimumSpeed: $createAudio1MinimumSpeed,
            createAudio1MaximumSpeed: $createAudio1MaximumSpeed,
            createAudio2MinimumSpeed: $createAudio2MinimumSpeed,
            createAudio2MaximumSpeed: $createAudio2MaximumSpeed,
            createAudio3MinimumSpeed: $createAudio3MinimumSpeed,
            createAudio3MaximumSpeed: $createAudio3MaximumSpeed,
            createAudio4MinimumSpeed: $createAudio4MinimumSpeed,
            createAudio4MaximumSpeed: $createAudio4MaximumSpeed,
            createAudio5MinimumSpeed: $createAudio5MinimumSpeed,
            createAudio5MaximumSpeed: $createAudio5MaximumSpeed,
            createSoundtrackTitle: $createSoundtrackTitle,
            createBaseTitle: $createBaseTitle,
            handleDoneAction: handleDoneAction
        )
    }
    

    
    // MARK: - Edit Page
    private var editScreen: some View {
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
    private var speedDetailScreen: some View {
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
        .persistentSystemOverlays(.hidden) // This will hide the home indicator
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
    private var settingsScreen: some View {
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
        // Reset all audio-related states
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
        
        // Reset speed settings
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
        
        // Reset navigation states
        showImportPage = false
        importedSoundtrackURL = nil
        showConfigurePage = false
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
        
        // Reset state before animation
        resetCreatePage()
        
        // Navigate back to mainScreen
        withAnimation(.easeInOut(duration: 0.5)) {
            showConfigurePage = false
            showCreatePage = false
        }
        
        print("Done pressed: Added new soundtrack: \(newTitle)")
        saveSoundtracks() // Save the updated soundtracks
    }
    
    private func prepareForSharing() -> [Any] {
        let soundtrack = pendingSoundtrack ?? soundtracks.first(where: { $0.title == audioController.currentSoundtrackTitle })
        guard let soundtrack = soundtrack else { return [] }
        
        let fileManager = FileManager.default
        
        // Create a temporary directory for sharing
        guard let tempBaseURL = try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: documentsDirectory,
            create: true
        ) else { return [] }
        
        // Create a folder with the soundtrack title (using a clean name)
        let soundtrackFolderName = "Dynamidrive - \(soundtrack.title)".replacingOccurrences(of: "/", with: "-")
        let soundtrackFolderURL = tempBaseURL.appendingPathComponent(soundtrackFolderName)
        
        do {
            try fileManager.createDirectory(at: soundtrackFolderURL, withIntermediateDirectories: true)
            
            // Copy each audio file to the folder with clean names
            for track in soundtrack.tracks {
                let sourceURL = documentsDirectory.appendingPathComponent(track.audioFileName)
                // Use a clean name for the shared file
                let cleanFileName = "\(track.displayName).mp3"
                let destinationURL = soundtrackFolderURL.appendingPathComponent(cleanFileName)
                
                if fileManager.fileExists(atPath: sourceURL.path) {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
            }
            
            // Create a metadata file with track information
            let metadataURL = soundtrackFolderURL.appendingPathComponent("soundtrack_info.txt")
            var metadataContent = "Dynamidrive Soundtrack: \(soundtrack.title)\n\n"
            
            for track in soundtrack.tracks {
                metadataContent += "Track: \(track.displayName)\n"
                if track.minimumSpeed == 0 && track.maximumSpeed == 0 {
                    metadataContent += "Always playing\n"
                } else {
                    metadataContent += "Speed range: \(track.minimumSpeed)-\(track.maximumSpeed) mph\n"
                }
                metadataContent += "Volume: \(track.maximumVolume)\n\n"
            }
            
            try metadataContent.write(to: metadataURL, atomically: true, encoding: .utf8)
            
            // Return the folder URL for sharing
            return [soundtrackFolderURL]
            
        } catch {
            print("Error preparing files for sharing: \(error)")
            // Clean up temp directory if something went wrong
            try? fileManager.removeItem(at: tempBaseURL)
            return []
        }
    }
    
    private func handleImport() {
        guard let importURL = importedSoundtrackURL else { return }
        
        let fileManager = FileManager.default
        
        do {
            // Read the metadata file
            let metadataURL = importURL.appendingPathComponent("soundtrack_info.txt")
            let metadataContent = try String(contentsOf: metadataURL, encoding: .utf8)
            let lines = metadataContent.components(separatedBy: .newlines)
            
            // Parse soundtrack title
            guard let titleLine = lines.first,
                  titleLine.hasPrefix("Dynamidrive Soundtrack: ") else {
                print("Invalid metadata format")
                return
            }
            
            let soundtrackTitle = String(titleLine.dropFirst("Dynamidrive Soundtrack: ".count))
            var tracks: [AudioController.SoundtrackData] = []
            var currentTrack: (name: String, minSpeed: Int, maxSpeed: Int, volume: Float)?
            
            // Parse track information
            for line in lines.dropFirst() {
                if line.hasPrefix("Track: ") {
                    // Save previous track if exists
                    if let track = currentTrack {
                        // Find the audio file
                        let audioFileName = "\(track.name).mp3"
                        let sourceURL = importURL.appendingPathComponent(audioFileName)
                        let destinationFileName = "Soundtrack\(soundtracks.count + 1)\(track.name)_\(UUID().uuidString).mp3"
                        let destinationURL = documentsDirectory.appendingPathComponent(destinationFileName)
                        
                        // Copy audio file
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                        
                        // Create track data
                        tracks.append(AudioController.SoundtrackData(
                            audioFileName: destinationFileName,
                            displayName: track.name,
                            maximumVolume: track.volume,
                            minimumSpeed: track.minSpeed,
                            maximumSpeed: track.maxSpeed
                        ))
                    }
                    
                    // Start new track
                    currentTrack = (
                        name: String(line.dropFirst("Track: ".count)),
                        minSpeed: 0,
                        maxSpeed: 0,
                        volume: 0.0
                    )
                } else if line == "Always playing" {
                    currentTrack?.minSpeed = 0
                    currentTrack?.maxSpeed = 0
                } else if line.hasPrefix("Speed range: ") {
                    let speedText = line.dropFirst("Speed range: ".count).dropLast(" mph".count)
                    let components = speedText.components(separatedBy: "-")
                    if components.count == 2,
                       let min = Int(components[0].trimmingCharacters(in: .whitespaces)),
                       let max = Int(components[1].trimmingCharacters(in: .whitespaces)) {
                        currentTrack?.minSpeed = min
                        currentTrack?.maxSpeed = max
                    }
                } else if line.hasPrefix("Volume: "),
                          let volume = Float(line.dropFirst("Volume: ".count)) {
                    currentTrack?.volume = volume
                }
            }
            
            // Add the last track
            if let track = currentTrack {
                let audioFileName = "\(track.name).mp3"
                let sourceURL = importURL.appendingPathComponent(audioFileName)
                let destinationFileName = "Soundtrack\(soundtracks.count + 1)\(track.name)_\(UUID().uuidString).mp3"
                let destinationURL = documentsDirectory.appendingPathComponent(destinationFileName)
                
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                
                tracks.append(AudioController.SoundtrackData(
                    audioFileName: destinationFileName,
                    displayName: track.name,
                    maximumVolume: track.volume,
                    minimumSpeed: track.minSpeed,
                    maximumSpeed: track.maxSpeed
                ))
            }
            
            // Create players for the tracks
            let players = tracks.map { track -> AVAudioPlayer? in
                let audioURL = documentsDirectory.appendingPathComponent(track.audioFileName)
                do {
                    let player = try AVAudioPlayer(contentsOf: audioURL)
                    player.volume = mapVolume(track.maximumVolume)
                    player.prepareToPlay()
                    return player
                } catch {
                    print("Failed to create player for \(track.audioFileName): \(error)")
                    return nil
                }
            }
            
            // Add the new soundtrack
            let newSoundtrack = Soundtrack(
                id: UUID(),
                title: soundtrackTitle,
                tracks: tracks,
                players: players
            )
            
            soundtracks.append(newSoundtrack)
            saveSoundtracks()
            
            // Reset states and navigate to main page
            withAnimation(.easeInOut(duration: 0.5)) {
                importedSoundtrackURL = nil
                resetCreatePage()
                showImportPage = false
                showCreatePage = false
                previousPage = .import
                currentPage = .main
            }
            
        } catch {
            print("Import failed: \(error)")
        }
    }
    
    // MARK: - Import Page
    private var importScreen: some View {
        ZStack {
            // Main content
            VStack(spacing: 20) {
                Spacer()
                
                // Confirmation card
                VStack(spacing: 30) {
                    Text("Do you want to add \(importedSoundtrackURL?.lastPathComponent ?? "") to your soundtracks?")
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 24))
                    
                    Button(action: {
                        handleImport()
                        withAnimation(.easeInOut(duration: 0.5)) {
                            previousPage = .import
                            currentPage = .main
                        }
                    }) {
                        Text("Add")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding()
                
                Spacer()
            }
            .padding()
            
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
                        importedSoundtrackURL = nil
                        withAnimation(.easeInOut(duration: 0.5)) {
                            previousPage = .import
                            currentPage = .create
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
    }
    
    // MARK: - AI Upload Page
        private var aiUploadScreen: some View {
        ZStack {
            // Mesh gradient background
            MeshGradientView()
                .opacity(showAIUploadPage ? 1 : 0)
                .animation(.easeInOut(duration: 1.0).delay(1.0), value: showAIUploadPage)
            
            // Main content
            VStack(spacing: 0) {
                Spacer()
                    .frame(height:1)
                
                // Upload section
                VStack(alignment: .leading, spacing: 15) {
                    Text("Upload a song")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Button(action: {
                        // Add file picker action here
                    }) {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 20))
                            Text("Select Audio File")
                                .font(.system(size: 17))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding()
                
                // Custom separator
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("OR")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 10)
                    
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                // YouTube search section
                VStack(alignment: .leading, spacing: 15) {
                    Text("Find a song on YouTube")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    TextField("Search Youtube...", text: .constant(""))
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(10)
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding()
                
                Spacer()
                
                // Instructions at the bottom
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(number: "1", text: "Upload an audio file")
                    InfoRow(number: "2", text: "Chose what stems to seperate")
                    InfoRow(number: "3", text: "AI separates the instruments")
                    InfoRow(number: "4", text: "Configure the speed ranges")
                    InfoRow(number: "5", text: "Create your new soundtrack")
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.bottom, 90) // Increased bottom padding to position instructions higher
            }
            
            // Empty stack between content and buttons
            ZStack {
            }
            .frame(height: 150)
            .allowsHitTesting(false)

            
            // Fixed bottom controls
            VStack {
                Spacer()
                HStack(spacing: 240) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showAIUploadPage = false
                            currentPage = .create
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    
                    // Invisible button for layout balance
                    Button(action: {}) {
                        Color.clear
                            .frame(width: 50, height: 50)
                    }
                    .disabled(true)
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
    
    private struct InfoRow: View {
        let number: String
        let text: String
        
        var body: some View {
            HStack(spacing: 15) {
                Text(number)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
                
                Text(text)
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
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
struct AudioBarsView: View {
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
    @Published var currentSoundtrackDistance: Double = 0.0  // Distance in miles
    @AppStorage("locationTrackingEnabled") private var locationTrackingEnabled: Bool = true
    private var lastLocation: CLLocation?
    private var isTrackingDistance: Bool = false
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
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
        
        // Calculate distance if tracking is enabled and locationTrackingEnabled is true
        if isTrackingDistance && locationTrackingEnabled {
            if let lastLoc = lastLocation {
                let distanceInMeters = location.distance(from: lastLoc)
                let distanceInMiles = distanceInMeters / 1609.34  // Convert meters to miles
                currentSoundtrackDistance += distanceInMiles
            }
            lastLocation = location
        }
        
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
    
    func stopDistanceTracking() {
        isTrackingDistance = false
        lastLocation = nil
    }
    
    func startDistanceTracking() {
        isTrackingDistance = true
        lastLocation = location
        currentSoundtrackDistance = 0.0  // Reset distance when starting new tracking
    }
    
    func resetAllDistanceData() {
        // Reset current soundtrack distance
        currentSoundtrackDistance = 0.0
        lastLocation = nil
        
        // Reset any stored distance data in UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
    }
}



struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: FolderPicker
        
        init(_ parent: FolderPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Custom Views
struct MeshGradientView: View {
    @State private var phase = 0.0
    @State private var colorPhases = [0.0, 0.3, 0.6, 0.9, 1.2, 1.5] // Different starting phases
    @State private var point1 = UnitPoint(x: 0.5, y: 0.3)
    @State private var point2 = UnitPoint(x: 0.3, y: 0.5)
    @State private var point3 = UnitPoint(x: 0.7, y: 0.7)
    @State private var opacity = 0.0
    
    let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()
    let colorTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    // Animation timing
    let fadeInDelay = 0.75
    let fadeInDuration = 3.0
    let fadeOutDuration = 0.2
    
    // Color arrays for each point
    let colors: [[Color]] = [
        [.yellow, .orange, .pink, .purple, .yellow],  // Top
        [.red, .pink, .purple, .orange, .red],        // Middle 1
        [.orange, .red, .pink, .yellow, .orange],     // Middle 2
        [.purple, .pink, .red, .orange, .purple],     // Middle 3
        [.blue, .purple, .cyan, .teal, .blue]         // Bottom
    ]
    
    // Get interpolated color based on phase
    func interpolateColor(_ colors: [Color], phase: Double) -> Color {
        let normalizedPhase = phase.truncatingRemainder(dividingBy: Double(colors.count - 1))
        let index = Int(normalizedPhase)
        let nextIndex = (index + 1) % colors.count
        let progress = normalizedPhase - Double(index)
        
        return .init(
            lerp(colors[index], colors[nextIndex], progress: progress)
        )
    }
    
    // Linear interpolation between colors
    func lerp(_ color1: Color, _ color2: Color, progress: Double) -> Color {
        let uiColor1 = UIColor(color1)
        let uiColor2 = UIColor(color2)
        
        var red1: CGFloat = 0, green1: CGFloat = 0, blue1: CGFloat = 0, alpha1: CGFloat = 0
        var red2: CGFloat = 0, green2: CGFloat = 0, blue2: CGFloat = 0, alpha2: CGFloat = 0
        
        uiColor1.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1)
        uiColor2.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2)
        
        return Color(
            red: red1 + (red2 - red1) * progress,
            green: green1 + (green2 - green1) * progress,
            blue: blue1 + (blue2 - blue1) * progress,
            opacity: alpha1 + (alpha2 - alpha1) * progress
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Top gradient
                RadialGradient(
                    gradient: Gradient(colors: [interpolateColor(colors[0], phase: colorPhases[0]).opacity(0.8),
                                              interpolateColor(colors[0], phase: colorPhases[0]).opacity(0)]),
                    center: .init(x: 0.5, y: 0.2),
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.5
                )
                
                // Middle gradients
                RadialGradient(
                    gradient: Gradient(colors: [interpolateColor(colors[1], phase: colorPhases[1]).opacity(0.8),
                                              interpolateColor(colors[1], phase: colorPhases[1]).opacity(0)]),
                    center: UnitPoint(
                        x: point1.x + sin(phase) * 0.1,
                        y: point1.y + cos(phase) * 0.1
                    ),
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.4
                )
                
                RadialGradient(
                    gradient: Gradient(colors: [interpolateColor(colors[2], phase: colorPhases[2]).opacity(0.6),
                                              interpolateColor(colors[2], phase: colorPhases[2]).opacity(0)]),
                    center: UnitPoint(
                        x: point2.x + cos(phase * 1.2) * 0.12,
                        y: point2.y + sin(phase * 1.2) * 0.12
                    ),
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.3
                )
                
                RadialGradient(
                    gradient: Gradient(colors: [interpolateColor(colors[3], phase: colorPhases[3]).opacity(0.6),
                                              interpolateColor(colors[3], phase: colorPhases[3]).opacity(0)]),
                    center: UnitPoint(
                        x: point3.x + sin(phase * 0.8) * 0.08,
                        y: point3.y + cos(phase * 0.8) * 0.08
                    ),
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.35
                )
                
                // Bottom gradient
                RadialGradient(
                    gradient: Gradient(colors: [interpolateColor(colors[4], phase: colorPhases[4]).opacity(0.8),
                                              interpolateColor(colors[4], phase: colorPhases[4]).opacity(0)]),
                    center: .init(x: 0.5, y: 0.8),
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.5
                )
            }
            .blur(radius: 60)
            .opacity(opacity)
        }
        .onAppear {
            // Start fade in after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeInDelay) {
                withAnimation(.easeInOut(duration: fadeInDuration)) {
                    opacity = 1.0
                }
            }
        }
        .onDisappear {
            // Quick fade out when view disappears
            withAnimation(.easeOut(duration: fadeOutDuration)) {
                opacity = 0.0
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: 0.02)) {
                phase += 0.02
            }
        }
        .onReceive(colorTimer) { _ in
            withAnimation(.linear(duration: 0.1)) {
                // Update each color phase at slightly different speeds
                colorPhases[0] += 0.008  // Top
                colorPhases[1] += 0.012  // Middle 1
                colorPhases[2] += 0.010  // Middle 2
                colorPhases[3] += 0.009  // Middle 3
                colorPhases[4] += 0.011  // Bottom
            }
        }
    }
}


