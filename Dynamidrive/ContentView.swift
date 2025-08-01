//
//  ContentView.swift
//  Dynamidrive
//
//  Created by Kai del Castillo on 3/1/25.
//


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
    var locationHandler: LocationHandler
    public var currentSoundtrackID: UUID? = nil // <-- Add this property
    @Published var isHushActive: Bool = false
    @Published var wasInterrupted: Bool = false // Track if an interruption occurred
    
    // Add a property to AudioController to hold the hush timer
    private var hushSpeedTimer: Timer?
    
    // Add a property to track hush cooldown
    private var hushCooldownUntil: Date? = nil
    
    private var nowPlayingMonitorTimer: Timer?
    
    struct SoundtrackData: Codable {
        let audioFileName: String
        let displayName: String
        var maximumVolume: Float
        let minimumSpeed: Int
        let maximumSpeed: Int
    }
    
    
    
    
    init(locationHandler: LocationHandler) {
        self.locationHandler = locationHandler
        setupAudioSession()
        setupRemoteControl()
        // Add observer for AVAudioSession interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        // Add observer for route changes (e.g., headphones unplugged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // Ensure audio session is properly configured for background playback after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupAudioSession()
        }
        
        // Also ensure audio session is properly configured after a longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupAudioSession()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Handle AVAudioSession interruptions (e.g., phone call, Siri, CarPlay, other music apps)
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        switch type {
        case .began:
            // Interruption began, pause playback if playing
            if isSoundtrackPlaying {
                pauseAllPlayersWithEffects()
                isSoundtrackPlaying = false // Update UI state
                wasInterrupted = true // Mark that an interruption occurred
            }
        case .ended:
            // Interruption ended, check if should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Pause all players and apply effects
                    pauseAllPlayersWithEffects()
                    // Set all to the minimum time
                    let times = currentPlayers.compactMap { $0?.currentTime }
                    let minTime = times.min() ?? 0.0
                    for player in currentPlayers {
                        player?.currentTime = minTime
                        player?.prepareToPlay() // Ensure the new position is set
                    }
                    masterPlaybackTime = minTime
                    // Wait a short moment, then resume playback (without toggling isSoundtrackPlaying/UI)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        let deviceCurrentTime = self.currentPlayers.first(where: { $0 != nil })??.deviceCurrentTime ?? 0
                        let startTime = deviceCurrentTime + 0.1
                        if let soundtrackID = self.currentSoundtrackID {
                            self.locationHandler.startDistanceTracking(for: soundtrackID)
                        }
                        for (index, player) in self.currentPlayers.enumerated() {
                            if let player = player {
                                player.currentTime = self.masterPlaybackTime
                                player.numberOfLoops = -1
                                if self.isHushActive {
                                    if index == 0 {
                                        let normalVolume = self.calculateVolumeForTrack(at: 0, speed: self.locationHandler.speedMPH)
                                        let hushVolume = normalVolume * 0.1
                                        player.volume = hushVolume
                                    } else {
                                        player.volume = 0.0
                                    }
                                } else {
                                    player.volume = self.calculateVolumeForTrack(at: index, speed: self.locationHandler.speedMPH)
                                }
                                player.play(atTime: startTime)
                            }
                        }
                        self.updateSyncTimer()
                        self.updateNowPlayingInfo()
                        self.isSoundtrackPlaying = true // Update UI state
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    // Detect when Now Playing session ends (e.g., user stops playback from Control Center)
    @objc private func handleNowPlayingSessionEnded(_ notification: Notification) {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        // If playback rate is 0 and we think we're playing, treat as session ended
        let playbackRate = (nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.floatValue ?? 1.0
        if playbackRate == 0.0 && isSoundtrackPlaying {
            print("[NowPlaying] Detected session ended externally. Stopping playback.")
            pauseAllPlayersWithEffects()
            isSoundtrackPlaying = false
            updateNowPlayingInfo()
        }
    }

    // Optionally, handle route changes (e.g., headphones unplugged)
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            // Headphones unplugged, pause playback
            if isSoundtrackPlaying {
                print("[AudioRoute] Headphones unplugged. Pausing playback.")
                pauseAllPlayersWithEffects()
                isSoundtrackPlaying = false
                updateNowPlayingInfo()
            }
        }
    }
    
    // Clear Now Playing info when app goes to background or stops
    func clearNowPlayingInfo() {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        nowPlayingInfoCenter.nowPlayingInfo = nil
        print("[AudioController] Cleared Now Playing info")
    }
    
    // Add this new method to adjust volumes based on speed
    func adjustVolumesForSpeed(_ speed: Double) {
        guard isSoundtrackPlaying else { return }
        // Prevent dynamic track volume changes if hush is active
        if isHushActive {
            // Enforce hush volumes regardless of speed
            for (index, player) in currentPlayers.enumerated() {
                guard let player = player, player.isPlaying else { continue }
                if index == 0 {
                    let normalVolume = calculateVolumeForTrack(at: 0, speed: speed)
                    let hushVolume = normalVolume * 0.1
                    fadeVolume(for: player, to: hushVolume, duration: 0.5, trackIndex: 0)
                } else {
                    fadeVolume(for: player, to: 0.0, duration: 0.5, trackIndex: index)
                }
            }
            return
        }
        for (index, player) in currentPlayers.enumerated() {
            if let player = player, player.isPlaying {
                let targetVolume = calculateVolumeForTrack(at: index, speed: speed)
                fadeVolume(for: player, to: targetVolume, duration: 1.0, trackIndex: index)
            }
        }
        updateNowPlayingInfo()
    }
    
    // Existing methods below remain unchanged
    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use more comprehensive options for background audio
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[AudioController] Audio session configured for background playback and Now Playing controls")
            
            // Verify the session is active
            if session.isOtherAudioPlaying {
                print("[AudioController] Other audio is playing, but our session is active")
            }
            
            // Ensure remote control events are enabled
            UIApplication.shared.beginReceivingRemoteControlEvents()
            
        } catch {
            print("[AudioController] Failed to set up audio session: \(error)")
            // Try a simpler approach if the first one fails
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                print("[AudioController] Audio session configured with simple settings")
                
                // Ensure remote control events are enabled even with simple settings
                UIApplication.shared.beginReceivingRemoteControlEvents()
                
            } catch {
                print("[AudioController] Failed to set up audio session with simple settings: \(error)")
            }
        }
    }
    
    func setupRemoteControl() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Remove existing targets to prevent duplicates
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self, !self.isSoundtrackPlaying else { return .commandFailed }
            print("[RemoteControl] Play command received")
            self.toggleSoundtrackPlayback()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self, self.isSoundtrackPlaying else { return .commandFailed }
            print("[RemoteControl] Pause command received")
            self.toggleSoundtrackPlayback()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            print("[RemoteControl] Toggle play/pause command received")
            self.toggleSoundtrackPlayback()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        
        print("[AudioController] Remote control setup completed")
    }
    
    func updateNowPlayingInfo() {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()
        
        // Always update Now Playing info, even if title is empty
        let title = currentSoundtrackTitle.isEmpty ? "Dynamidrive" : currentSoundtrackTitle
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Speed: \(Int(locationHandler.speedMPH.rounded())) mph"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Dynamidrive Soundtracks"
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isSoundtrackPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        // Use the actual player's currentTime if available
        let currentTime = currentPlayers.first(where: { $0 != nil })??.currentTime ?? masterPlaybackTime
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

        if let player = currentPlayers.first, let duration = player?.duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        if let appIcon = UIImage(named: "AlbumArt") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: appIcon.size) { _ in appIcon }
        } else if let fallbackIcon = UIImage(systemName: "music.note")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: fallbackIcon.size) { _ in fallbackIcon }
        }
        
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        print("[AudioController] Updated Now Playing info: \(title), playing: \(isSoundtrackPlaying)")
    }
    
    func toggleSoundtrackPlayback() {
        print("[AudioController] Toggle soundtrack playback called")
        print("[AudioController] Current state: isSoundtrackPlaying=\(isSoundtrackPlaying)")
        print("[AudioController] Players count: \(currentPlayers.count)")
        
        let syncTolerance: TimeInterval = 0.001
        if isSoundtrackPlaying {
            print("[AudioController] Pausing playback")
            pauseAllPlayersWithEffects()
            stopNowPlayingMonitor()
            
            // Update now playing info to reflect paused state
            updateNowPlayingInfo()
        } else {
            print("[AudioController] Starting playback")
            // Always re-activate audio session and re-set Now Playing info before starting playback
            setupAudioSession()
            
            // Verify audio session is active before proceeding
            let session = AVAudioSession.sharedInstance()
            if !session.isOtherAudioPlaying {
                print("[AudioController] Audio session is active and ready for playback")
            } else {
                print("[AudioController] Warning: Other audio is playing, but continuing with playback")
            }
            
            // Ensure remote control is set up
            setupRemoteControl()
            
            // Ensure audio session is properly configured for background playback
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                print("[AudioController] Audio session re-configured for background playback")
            } catch {
                print("[AudioController] Failed to re-configure audio session: \(error)")
            }
            
            updateNowPlayingInfo()
            
            // Ensure now playing info is properly set for background playback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.updateNowPlayingInfo()
            }
            
            // --- Synchronize all players before playing ---
            let referenceTimes = currentPlayers.compactMap { $0?.currentTime }
            let allExact = referenceTimes.dropFirst().allSatisfy { abs($0 - (referenceTimes.first ?? 0.0)) < syncTolerance }
            print("[DEBUG] Checking sync before playback: times = \(referenceTimes), allExact = \(allExact)")
            if !allExact {
                // Pause all players, set all to the minimum (earliest) playback time, then start playback from that position
                print("[DEBUG] Not all tracks are in sync. Pausing and aligning to min time.")
                currentPlayers.forEach { $0?.pause() }
                let minTime = referenceTimes.min() ?? 0.0
                for player in currentPlayers {
                    player?.currentTime = minTime
                }
                masterPlaybackTime = minTime
            }
            let deviceCurrentTime = currentPlayers.first(where: { $0 != nil })??.deviceCurrentTime ?? 0
            let startTime = deviceCurrentTime + 0.1
            if let soundtrackID = currentSoundtrackID {
                locationHandler.startDistanceTracking(for: soundtrackID)
            }
            for (index, player) in currentPlayers.enumerated() {
                if let player = player {
                    player.currentTime = masterPlaybackTime
                    player.numberOfLoops = -1
                    if isHushActive {
                        if index == 0 {
                            let normalVolume = calculateVolumeForTrack(at: 0, speed: locationHandler.speedMPH)
                            let hushVolume = normalVolume * 0.1
                            player.volume = hushVolume
                        } else {
                            player.volume = 0.0
                        }
                    } else {
                        player.volume = calculateVolumeForTrack(at: index, speed: locationHandler.speedMPH)
                    }
                    print("[AudioController] Player \(index) volume: \(player.volume)")
                    player.play(atTime: startTime)
                    print("[AudioController] Player \(index) play() called")
                }
            }
            updateSyncTimer()
            startNowPlayingMonitor()
            
            // Ensure now playing info is updated immediately after starting playback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateNowPlayingInfo()
            }
            
            // Also update after a longer delay to ensure it's properly set
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.updateNowPlayingInfo()
            }
            
            // Also update after an even longer delay to ensure it's properly set
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateNowPlayingInfo()
            }
            
            // If playback was previously interrupted, immediately pause, sync, and play again (without toggling isSoundtrackPlaying)
            if wasInterrupted {
                wasInterrupted = false // Reset immediately to prevent re-entry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    print("[DEBUG] wasInterrupted: Pausing all players for adjustment.")
                    self.currentPlayers.forEach { $0?.pause() }
                    let beforeTimes = self.currentPlayers.compactMap { $0?.currentTime }
                    print("[DEBUG] wasInterrupted: Track times before adjustment: \(beforeTimes)")
                    let times = self.currentPlayers.compactMap { $0?.currentTime }
                    let minTime = times.min() ?? 0.0
                    // Only adjust if not already within tolerance
                    let allWithinTolerance = times.dropFirst().allSatisfy { abs($0 - (times.first ?? 0.0)) < syncTolerance }
                    if !allWithinTolerance {
                        for player in self.currentPlayers {
                            player?.currentTime = minTime
                            player?.prepareToPlay()
                        }
                        let afterTimes = self.currentPlayers.compactMap { $0?.currentTime }
                        print("[DEBUG] wasInterrupted: Track times after adjustment: \(afterTimes), all set to minTime: \(minTime)")
                        self.masterPlaybackTime = minTime
                    } else {
                        print("[DEBUG] wasInterrupted: All tracks already within tolerance (", syncTolerance, "), skipping adjustment.")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        print("[DEBUG] wasInterrupted: Playing all tracks after adjustment.")
                        let deviceCurrentTime = self.currentPlayers.first(where: { $0 != nil })??.deviceCurrentTime ?? 0
                        let startTime = deviceCurrentTime + 0.1
                        for (index, player) in self.currentPlayers.enumerated() {
                            if let player = player {
                                player.currentTime = self.masterPlaybackTime
                                player.numberOfLoops = -1
                                if self.isHushActive {
                                    if index == 0 {
                                        let normalVolume = self.calculateVolumeForTrack(at: 0, speed: self.locationHandler.speedMPH)
                                        let hushVolume = normalVolume * 0.1
                                        player.volume = hushVolume
                                    } else {
                                        player.volume = 0.0
                                    }
                                } else {
                                    player.volume = self.calculateVolumeForTrack(at: index, speed: self.locationHandler.speedMPH)
                                }
                                print("[DEBUG] wasInterrupted: Playing track \(index) at time \(player.currentTime)")
                                player.play(atTime: startTime)
                            }
                        }
                        self.updateSyncTimer()
                        self.updateNowPlayingInfo()
                        self.isSoundtrackPlaying = true
                        let playingStates = self.currentPlayers.map { $0?.isPlaying ?? false }
                        print("[DEBUG] wasInterrupted: Adjustment complete. isSoundtrackPlaying=\(self.isSoundtrackPlaying), player states: \(playingStates)")
                        // Simulate a pause button press, then after 1 second, a play button press
                        print("[DEBUG] wasInterrupted: Simulating pause button press after interruption.")
                        self.toggleSoundtrackPlayback() // Simulate pause
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            print("[DEBUG] wasInterrupted: Simulating play button press after 1s.")
                            self.toggleSoundtrackPlayback() // Simulate play
                        }
                    }
                }
            }
        }
        isSoundtrackPlaying.toggle()
        updateNowPlayingInfo()
    }
    
    // Monitor if all players have stopped (Now Playing session ended externally)
    private func startNowPlayingMonitor() {
        stopNowPlayingMonitor()
        nowPlayingMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let anyPlaying = self.currentPlayers.contains { $0?.isPlaying == true }
            if !anyPlaying && self.isSoundtrackPlaying {
                print("[NowPlayingMonitor] All players stopped. Detected external session end.")
                self.isSoundtrackPlaying = false
                self.updateNowPlayingInfo()
                self.stopNowPlayingMonitor()
            }
        }
    }
    private func stopNowPlayingMonitor() {
        nowPlayingMonitorTimer?.invalidate()
        nowPlayingMonitorTimer = nil
    }
    
    func setCurrentSoundtrack(id: UUID, tracks: [SoundtrackData], players: [AVAudioPlayer?], title: String) {
        print("[AudioController] Setting current soundtrack: \(title)")
        print("[AudioController] Tracks count: \(tracks.count)")
        print("[AudioController] Players count: \(players.count)")
        
        // Debug: Check if players are valid
        for (index, player) in players.enumerated() {
            if let player = player {
                print("[AudioController] Player \(index): valid, duration=\(player.duration) seconds")
            } else {
                print("[AudioController] Player \(index): nil")
            }
        }
        
        let wasPlaying = isSoundtrackPlaying
        let wasSameSoundtrack = currentSoundtrackTitle == title
        
        // If switching to a different soundtrack, pause current playback
        if !wasSameSoundtrack {
            if isSoundtrackPlaying {
                currentPlayers.forEach { $0?.pause() }
                locationHandler.stopDistanceTracking()
                updateSyncTimer()
                isSoundtrackPlaying = false
            }
            masterPlaybackTime = 0
            // Reset all players' currentTime to 0 when switching soundtracks
            for player in currentPlayers {
                player?.currentTime = 0
                player?.prepareToPlay()
            }
        }
        
        // Always update tracks and players (even for the same soundtrack)
        currentTracks = tracks
        currentPlayers = players
        currentSoundtrackTitle = title
        currentSoundtrackID = id
        
        // Set initial volumes respecting hush state
        for (index, player) in currentPlayers.enumerated() {
            if let player = player {
                if isHushActive {
                    if index == 0 {
                        let normalVolume = calculateVolumeForTrack(at: 0, speed: locationHandler.speedMPH)
                        let hushVolume = normalVolume * 0.1
                        player.volume = hushVolume
                    } else {
                        player.volume = 0.0
                    }
                } else {
                    player.volume = calculateVolumeForTrack(at: index, speed: locationHandler.speedMPH)
                }
            }
        }
        
        // Ensure now playing info is updated immediately
        updateNowPlayingInfo()
        
        // Also update after a short delay to ensure it's properly set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateNowPlayingInfo()
        }
        
        // Also update after a longer delay to ensure it's properly set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateNowPlayingInfo()
        }
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
            // Do NOT reset masterPlaybackTime here!
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
        
        // If both minimum and maximum are 0, it's a base track that always plays
        if minSpeed == 0 && maxSpeed == 0 {
            return maxVolume
        }
        
        // If minimum and maximum are the same but not 0, it's a threshold track
        if minSpeed == maxSpeed && minSpeed != 0 {
            return speed >= minSpeed ? maxVolume : 0.0
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
    
    func fadeVolume(for player: AVAudioPlayer?, to targetVolume: Float, duration: TimeInterval = 1.0, trackIndex: Int? = nil) {
        guard let player = player else { return }
        let steps = 20
        let stepInterval = duration / Double(steps)
        let startVolume = player.volume
        var effectiveTarget = targetVolume
        if isHushActive, let idx = trackIndex {
            if idx == 0 {
                // Base track: 10% of normal
                let normalVolume = calculateVolumeForTrack(at: 0, speed: locationHandler.speedMPH)
                effectiveTarget = normalVolume * 0.1
            } else {
                // Dynamic tracks: mute
                effectiveTarget = 0.0
            }
        }
        let volumeStep = (effectiveTarget - startVolume) / Float(steps)
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepInterval * Double(i)) {
                // Re-check hush state at each step for robustness
                var stepTarget = effectiveTarget
                if self.isHushActive, let idx = trackIndex {
                    if idx == 0 {
                        let normalVolume = self.calculateVolumeForTrack(at: 0, speed: self.locationHandler.speedMPH)
                        stepTarget = normalVolume * 0.1
                    } else {
                        stepTarget = 0.0
                    }
                }
                player.volume = max(0.0, min(2.0, startVolume + volumeStep * Float(i)))
                // Clamp to hush volume if hush is on
                if self.isHushActive, let idx = trackIndex {
                    if idx == 0 {
                        let normalVolume = self.calculateVolumeForTrack(at: 0, speed: self.locationHandler.speedMPH)
                        player.volume = min(player.volume, normalVolume * 0.1)
                    } else {
                        player.volume = 0.0
                    }
                }
            }
        }
    }
    
    // Hush logic: temporarily mute dynamic tracks and set their volume to 30% of normal
    func activateHush() {
        // Prevent activation if cooldown is active
        if let cooldown = hushCooldownUntil, cooldown > Date() {
            return
        }
        guard isSoundtrackPlaying else { return }
        isHushActive = true
        locationHandler.pauseSpeedUpdates()
        locationHandler.speedMPH = 0.0
        adjustVolumesForSpeed(0.0) // Immediately apply hush volumes
        // Start a repeating timer to keep speed at 0 every 5 seconds while hush is active
        hushSpeedTimer?.invalidate()
        hushSpeedTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isHushActive else { return }
            self.locationHandler.speedMPH = 0.0
        }
    }
    
    func deactivateHush() {
        guard isSoundtrackPlaying else { return }
        isHushActive = false
        hushSpeedTimer?.invalidate()
        hushSpeedTimer = nil
        // Set cooldown for 5 seconds
        hushCooldownUntil = Date().addingTimeInterval(5.0)
        locationHandler.resumeSpeedUpdates()
        for (index, player) in currentPlayers.enumerated() {
            guard let player = player, player.isPlaying else { continue }
            // Restore normal volume
            let normalVolume = calculateVolumeForTrack(at: index, speed: locationHandler.speedMPH)
            fadeVolume(for: player, to: normalVolume, duration: 0.5)
        }
        // After hush is off, allow normal volume logic to resume
        adjustVolumesForSpeed(locationHandler.speedMPH)
    }
    
    // New: Pause all players and apply all effects, but do not toggle UI state
    private func pauseAllPlayersWithEffects() {
        if let firstPlayer = currentPlayers.first(where: { $0?.isPlaying ?? false }) {
            masterPlaybackTime = firstPlayer?.currentTime ?? 0.0
        }
        currentPlayers.forEach { $0?.pause() }
        locationHandler.stopDistanceTracking()
        updateSyncTimer()
    }
}

// MARK: - Soundtrack Struct
struct Soundtrack: Identifiable, Codable {
    let id: UUID
    let title: String
    let tracks: [AudioController.SoundtrackData]
    let cardColor: Color
    let isAI: Bool // Flag to indicate if this soundtrack was created with AI
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
        case cardColor
        case isAI
    }
    
    // Custom initializer for decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.tracks = try container.decode([AudioController.SoundtrackData].self, forKey: .tracks)
        self.cardColor = try container.decode(Color.self, forKey: .cardColor)
        // Handle backward compatibility for existing soundtracks that don't have isAI property
        if let isAI = try? container.decode(Bool.self, forKey: .isAI) {
            self.isAI = isAI
        } else {
            self.isAI = false // Default to false for existing soundtracks
        }
        self.players = [] // Initialize as empty; will be set during loadSoundtracks
    }
    
    // Custom initializer for encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(cardColor, forKey: .cardColor)
        try container.encode(isAI, forKey: .isAI)
        // players is not encoded
    }
    
    // Convenience initializer for creating a new Soundtrack
    init(id: UUID, title: String, tracks: [AudioController.SoundtrackData], players: [AVAudioPlayer?], cardColor: Color = .clear, isAI: Bool = false) {
        self.id = id
        self.title = title
        self.tracks = tracks
        self.players = players
        self.cardColor = cardColor
        self.isAI = isAI
    }
}


class AppDelegate: NSObject, UIApplicationDelegate {
    let audioController: AudioController
    let locationHandler = LocationHandler()
    
    // Add a static property to track current page for orientation control
    static var currentPage: AppPage = .loading
    
    override init() {
        self.audioController = AudioController(locationHandler: locationHandler)
        super.init()
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Force dark mode for the entire app
        if let windowScene = application.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = .dark
            }
        }
        
        // Alternative method: force dark mode on the main window
        if let window = application.windows.first {
            window.overrideUserInterfaceStyle = .dark
        }
        
        // Set up audio session for background playback
        audioController.setupAudioSession()
        
        // Ensure audio session is properly configured for background playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[AppDelegate] Audio session configured for background playback on app launch")
        } catch {
            print("[AppDelegate] Failed to configure audio session on app launch: \(error)")
        }
        
        // LocationHandler will check hasGrantedLocationPermission internally
        locationHandler.startLocationUpdates()
        return true
    }
    
    // Add this method to control orientation dynamically
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Only allow rotation on SpeedDetailPage
        if AppDelegate.currentPage == .speedDetail {
            return .allButUpsideDown
        } else {
            return .portrait
        }
    }
    
    // Handle app entering background
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("[AppDelegate] App entered background")
        // Keep audio session active for background playback
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AppDelegate] Failed to keep audio session active: \(error)")
        }
    }
    
    // Handle app entering foreground
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("[AppDelegate] App entering foreground")
        // Re-setup audio session if needed
        audioController.setupAudioSession()
        
        // Update now playing info if there's active playback
        if audioController.isSoundtrackPlaying {
            audioController.updateNowPlayingInfo()
        }
    }
    
    // Handle app becoming active
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("[AppDelegate] App became active")
        // Ensure audio session is properly configured
        audioController.setupAudioSession()
        
        // Update now playing info if there's active playback
        if audioController.isSoundtrackPlaying {
            audioController.updateNowPlayingInfo()
        }
    }
    
    // Handle app resigning active
    func applicationWillResignActive(_ application: UIApplication) {
        print("[AppDelegate] App will resign active")
        // Ensure audio session remains active for background playback
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AppDelegate] Failed to keep audio session active: \(error)")
        }
    }
}

extension Soundtrack: Equatable {
    static func == (lhs: Soundtrack, rhs: Soundtrack) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.tracks == rhs.tracks &&
               lhs.cardColor == rhs.cardColor
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
        Text("Upload one file and tracks with different instruments will be generated for you. This feature is coming soon!")
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
    @State private var volumePageSource: AppPage? = nil // Track which page the volume page came from
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
    @EnvironmentObject var locationHandler: LocationHandler
    @EnvironmentObject private var audioController: AudioController
    @State private var soundtracks: [Soundtrack] = []
    @State private var displayedSpeed: Int = 0 // For the numerical display (no animation)
    @State private var animatedSpeed: Double = 0.0 // For the gauge (with animation)
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCompletedInitialLoad = false
    @State private var isReturningFromConfigure = false
    @AppStorage("mapStyle") private var mapStyle: MapStyle = .standard
    @AppStorage("backgroundType") private var backgroundType: BackgroundType = .map
    @AppStorage("hasGrantedLocationPermission") private var hasGrantedLocationPermission = false
    
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
        case muted // New case for Muted map style
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
    @State private var previewTrackingTimer: Timer?
    @State private var isMainScreenEditMode = false
    @State private var useGaugeWithValues: Bool = false
    @State private var gradientRotation: Double = 0 // New state for gradient rotation
    @State private var createTip = CreatePageTip()
    @State private var editTip = EditPageTip()
    @State private var animateCards: Bool = false // Start invisible
    @State private var hasAnimatedOnce: Bool = false
    @State private var wasPlaybackSheetOpenForSpeedDetail: Bool = false // Track if playback sheet was open before speed detail
    @State private var wasPlaybackSheetOpenForEdit: Bool = false // Track if playback sheet was open before edit page
    @State private var selectedCardColor: Color = .clear // New state for card color selection
    @State private var importSoundtrackTitle: String = ""
    @State private var importTracks: [ImportTrack] = []
    @State private var importTempFolder: URL? = nil
    @State private var importError: String? = nil
    
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
    
    // MARK: State for Uploading
    @State private var showUploading: Bool = false // Controls UploadingScreen
    @State private var isUploading: Bool = false // Controls text in UploadingScreen
    @State private var isDownloading: Bool = false // Controls downloading text in UploadingScreen
    
    @State private var currentPage: AppPage = .loading
    @State private var previousPage: AppPage? = nil
    
    
    private var documentsDirectory: URL {
        let fileManager = FileManager.default
        guard let baseDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Failed to access documents directory")
        }
        
        print("[ContentView] Documents directory path: \(baseDirectory.path)")
        
        // Create a more visible directory structure
        let visibleDirectory = baseDirectory.appendingPathComponent("Dynamidrive_Visible_Files")
        
        // Create the directory if it doesn't exist
        if !fileManager.fileExists(atPath: visibleDirectory.path) {
            do {
                try fileManager.createDirectory(at: visibleDirectory, withIntermediateDirectories: true, attributes: nil)
                print("[ContentView] Created visible directory: \(visibleDirectory)")
                
                // Create a README file to make the folder visible
                let readmeURL = visibleDirectory.appendingPathComponent("README.txt")
                let readmeContent = """
Dynamidrive App Files
=====================

This folder contains files created by the Dynamidrive app.

Created on: \(Date())

Contents:
- soundtracks.json: Soundtrack metadata
- Various .mp3 files: Audio tracks
- .dynamidrive_data/: Hidden app data

To find this folder in Files app:
1. Open Files app
2. Go to "On My iPhone/iPad"
3. Look for "Dynamidrive" folder
4. This folder should be inside

If you can't see it, try:
- Files app > Browse > On My iPhone/iPad
- Files app > Recents
- Files app > Search for "Dynamidrive"
"""
                try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
                print("[ContentView] Created README.txt file")
                
            } catch {
                print("Error creating visible directory: \(error)")
            }
        }
        
        // Create a hidden directory for soundtrack files
        let hiddenDirectory = baseDirectory.appendingPathComponent(".dynamidrive_data")
        
        // Create the directory if it doesn't exist
        if !fileManager.fileExists(atPath: hiddenDirectory.path) {
            do {
                try fileManager.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true, attributes: nil)
                
           
                let nomediaPath = hiddenDirectory.appendingPathComponent(".nomedia")
                if !fileManager.fileExists(atPath: nomediaPath.path) {
                    fileManager.createFile(atPath: nomediaPath.path, contents: nil)
                }
            } catch {
                print("Error creating hidden directory: \(error)")
            }
        }
        
        return baseDirectory
    }
    
    // MARK: Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Fixed map and blur background for all pages
                if backgroundType == .map && hasGrantedLocationPermission {
                    if mapStyle == .muted {
                        let debugCoordinate = locationHandler.location?.coordinate
                        MutedMapViewContainer(
                            styleURL: "mapbox://styles/kaianthonyd/cmd4pbdi6035j01srdizv9b0a",
                            coordinate: debugCoordinate,
                            currentPage: $currentPage,
                        )
                        .onAppear {
                            print("Coordinate passed to MutedMapView:", debugCoordinate as Any)
                        }
                        .onChange(of: debugCoordinate) { newValue in
                            print("Coordinate passed to MutedMapView changed:", newValue as Any)
                        }
                    } else {
                        Map(position: $cameraPosition, interactionModes: []) {
                            UserAnnotation()
                        }
                        .mapStyle(
                            mapStyle == .satellite ? .imagery(elevation: .realistic) : .standard
                        )
                        .mapControlVisibility(.hidden)
                        .ignoresSafeArea(.all)
                        .onAppear {
                            cameraPosition = .userLocation(followsHeading: false, fallback: .camera(MapCamera(
                                centerCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                                distance: 1000,
                                heading: 0
                            )))
                        }
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
                    .opacity(backgroundType == .map && mapStyle == .muted ? 0 : 1)
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
                                .transition(GlobalPageTransition)
                        case .main:
                            mainScreen
                                .transition(GlobalPageTransition)
                        case .create:
                            CreatePage(
                                showCreatePage: $showCreatePage,
                                showConfigurePage: $showConfigurePage,
                                showVolumePage: $showVolumePage,
                                createBaseAudioURL: $createBaseAudioURL,
                                createBasePlayer: $createBasePlayer,
                                createBaseIsPlaying: $createBaseIsPlaying,
                                createBaseOffset: $createBaseOffset,
                                createBaseShowingFilePicker: $createBaseShowingFilePicker,
                                createBaseVolume: $createBaseVolume,
                                createBaseTitle: $createBaseTitle,
                                createAdditionalZStacks: $createAdditionalZStacks,
                                createAdditionalTitles: $createAdditionalTitles,
                                createAdditionalAlwaysPlaying: $createAdditionalAlwaysPlaying,
                                createSoundtrackTitle: $createSoundtrackTitle,
                                createReferenceLength: $createReferenceLength,
                                createNextID: $createNextID,
                                createAudio1MinimumSpeed: $createAudio1MinimumSpeed,
                                createAudio1MaximumSpeed: $createAudio1MaximumSpeed,
                                showAIUploadPage: $showAIUploadPage,
                                gradientRotation: $gradientRotation,
                                showInfoPage: $showInfoPage,
                                currentPage: $currentPage,
                                previousPage: $previousPage,
                                createTip: $createTip,
                                showLengthMismatchAlert: $showLengthMismatchAlert,
                                soundtracks: $soundtracks,
                                saveSoundtracks: saveSoundtracks
                            )
                            .environmentObject(audioController)
                            .transition(GlobalPageTransition)
                        case .configure:
                            configureScreen
                                .transition(GlobalPageTransition)
                        case .aiConfigure:
                            aiConfigureScreen
                                .transition(GlobalPageTransition)
                        case .volume:
                            volumeScreen
                                .transition(GlobalPageTransition)
                        case .playback:
                            EmptyView()
                                .transition(GlobalPageTransition)
                        case .edit:
                            EditPage(
                                showEditPage: $showEditPage,
                                pendingSoundtrack: $pendingSoundtrack,
                                soundtracks: $soundtracks,
                                saveSoundtracks: saveSoundtracks
                            )
                            .environmentObject(audioController)
                            .transition(GlobalPageTransition)
                        case .speedDetail:
                            SpeedDetailPage(
                                showSpeedDetailPage: $showSpeedDetailPage,
                                showSettingsPage: $showSettingsPage,
                                areButtonsVisible: $areButtonsVisible,
                                animatedSpeed: $animatedSpeed,
                                useBlackBackground: $useBlackBackground,
                                landscapeGaugeStyle: $landscapeGaugeStyle,
                                landscapeIndicatorStyle: $landscapeIndicatorStyle,
                                landscapeShowMinMax: $landscapeShowMinMax,
                                landscapeShowCurrentSpeed: $landscapeShowCurrentSpeed,
                                landscapeShowSoundtrackTitle: $landscapeShowSoundtrackTitle,
                                syncCircularGaugeSettings: $syncCircularGaugeSettings,
                                gaugeFontStyle: $gaugeFontStyle,
                                showPortraitSpeed: $showPortraitSpeed,
                                portraitGaugeStyle: $portraitGaugeStyle,
                                portraitShowMinMax: $portraitShowMinMax,
                                pendingSoundtrack: $pendingSoundtrack,
                                audioController: .constant(audioController),
                                deviceOrientation: $deviceOrientation,
                                startInactivityTimer: startInactivityTimer,
                                invalidateInactivityTimer: invalidateInactivityTimer
                            )
                            .transition(GlobalPageTransition)
                        case .settings:
                            settingsScreen
                                .transition(GlobalPageTransition)
                        case .import:
                            importScreen
                                .transition(GlobalPageTransition)
                        case .aiUpload:
                            AIUploadPage(
                                onBack: {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        currentPage = .create // Go back to the create page
                                    }
                                },
                                showCreatePage: $showCreatePage,
                                showConfigurePage: $showConfigurePage,
                                createBaseAudioURL: $createBaseAudioURL,
                                createBasePlayer: $createBasePlayer,
                                createBaseIsPlaying: $createBaseIsPlaying,
                                createBaseOffset: $createBaseOffset,
                                createBaseShowingFilePicker: $createBaseShowingFilePicker,
                                createBaseVolume: $createBaseVolume,
                                createAdditionalZStacks: $createAdditionalZStacks,
                                createAdditionalTitles: $createAdditionalTitles,
                                createAdditionalAlwaysPlaying: $createAdditionalAlwaysPlaying,
                                createBaseTitle: $createBaseTitle,
                                createSoundtrackTitle: $createSoundtrackTitle,
                                createReferenceLength: $createReferenceLength,
                                createNextID: $createNextID,
                                currentPage: $currentPage,
                                showUploading: $showUploading,
                                isUploading: $isUploading,
                                isDownloading: $isDownloading,
                                soundtracks: $soundtracks,
                                createAudio1MinimumSpeed: $createAudio1MinimumSpeed,
                                createAudio1MaximumSpeed: $createAudio1MaximumSpeed,
                                createAudio2MinimumSpeed: $createAudio2MinimumSpeed,
                                createAudio2MaximumSpeed: $createAudio2MaximumSpeed,
                                createAudio3MinimumSpeed: $createAudio3MinimumSpeed,
                                createAudio3MaximumSpeed: $createAudio3MaximumSpeed,
                                createAudio4MinimumSpeed: $createAudio4MinimumSpeed,
                                createAudio4MaximumSpeed: $createAudio4MaximumSpeed,
                                createAudio5MinimumSpeed: $createAudio5MinimumSpeed,
                                createAudio5MaximumSpeed: $createAudio5MaximumSpeed
                            )
                            .transition(GlobalPageTransition)
                        case .uploading:
                            UploadingScreen(
                                isVisible: $showUploading,
                                isUploading: $isUploading,
                                isDownloading: $isDownloading
                            )
                            .transition(GlobalPageTransition)
                        case .masterSettings:
                            MasterSettings(currentPage: $currentPage)
                                .environmentObject(locationHandler)
                                .transition(GlobalPageTransition)
                        case .layout:
                            LayoutPage(showingLayoutPage: Binding(
                                get: { currentPage == .layout },
                                set: { show in if (!show) { currentPage = .masterSettings } }
                            ))
                            .transition(GlobalPageTransition)
                        case .importConfirmation:
                            EmptyView()
                                .transition(GlobalPageTransition)
                        }
                    }
                    .zIndex(9)
                }
            }
        }
        .statusBar(hidden: currentPage == .loading || currentPage == .speedDetail || currentPage == .uploading || !hasCompletedInitialLoad)
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
                defaults.set(true, forKey: "hasLaunchedBefore")
            }
        }
        .onChange(of: isLoading, initial: false) { _, newValue in
            if !newValue && !hasCompletedInitialLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    hasCompletedInitialLoad = true
                    currentPage = .main
                    isReturningFromConfigure = false
                    
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            animateCards = true
                        }
                    }
                }
            }
        }
        .onChange(of: showCreatePage, initial: false) { _, newValue in
            print("showCreatePage changed to: \(newValue), currentPage: \(currentPage)")
            withAnimation(.easeInOut(duration: 0.2)) {
                let oldPage = currentPage
                previousPage = newValue ? oldPage : .create
                currentPage = newValue ? .create : .main
                isReturningFromConfigure = false
            }
            print("After showCreatePage change: currentPage: \(currentPage)")
        }
        .onChange(of: showConfigurePage, initial: false) { _, newValue in
            print("showConfigurePage changed to: \(newValue), currentPage: \(currentPage), showCreatePage: \(showCreatePage)")
            withAnimation(.easeInOut(duration: 0.2)) {
                let oldPage = currentPage
                isReturningFromConfigure = !newValue
                previousPage = newValue ? oldPage : .configure
                if newValue {
                    currentPage = .configure
                } else {
                    if oldPage == .configure && showCreatePage {
                        currentPage = .create
                    } else {
                        currentPage = .main
                    }
                }
            }
            print("After showConfigurePage change: currentPage: \(currentPage), showCreatePage: \(showCreatePage)")
        }
        .onChange(of: showVolumePage, initial: false) { oldValue, newValue in
            print("showVolumePage changed to: \(newValue), volumePageSource: \(volumePageSource.map { String(describing: $0) } ?? "nil")")
            print("Current page before change: \(currentPage)")
            withAnimation(.easeInOut(duration: 0.2)) {
                let oldPage = currentPage
                previousPage = newValue ? oldPage : .volume
                if newValue {
                    // Store the current page as the source when opening volume page
                    volumePageSource = currentPage
                    print("Setting volumePageSource to: \(currentPage)")
                    currentPage = .volume
                } else {
                    // Navigate back to the source page when closing volume page
                    if let source = volumePageSource {
                        print("Navigating back to source: \(source)")
                        currentPage = source
                    } else {
                        // Fallback to configure page if no source is set
                        print("No source set, falling back to configure")
                        currentPage = .configure
                    }
                }
            }
            print("After showVolumePage change: currentPage: \(currentPage)")
            
            // Reset volumePageSource after navigation is complete
            if !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    volumePageSource = nil
                    print("Reset volumePageSource to nil")
                }
            }
        }
        .onChange(of: showPlaybackPage, initial: false) { _, newValue in
            // Don't change currentPage when playback sheet is shown/hidden
            // The playback page is presented as a sheet overlay, so the main page should remain visible
            // Only handle the case when closing the sheet and we need to return to a specific page
            if !newValue && !showSpeedDetailPage && !showEditPage {
                // When closing playback sheet and no other pages are open, ensure we're on main page
                if currentPage == .playback {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = .main
                    }
                }
            }
        }
        .onChange(of: locationHandler.speedMPH) { oldValue, newSpeed in
            displayedSpeed = Int(newSpeed.rounded())
            
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedSpeed = newSpeed
            }
            
            withAnimation(.easeInOut(duration: 1.0)) {
                if audioController.isHushActive {
                    // Only update base track (index 0) if hush is active
                    if let player = audioController.currentPlayers.first, let basePlayer = player, basePlayer.isPlaying {
                        let targetVolume = audioController.calculateVolumeForTrack(at: 0, speed: newSpeed)
                        audioController.fadeVolume(for: basePlayer, to: targetVolume, duration: 1.0)
                    }
                } else {
                    for (index, player) in audioController.currentPlayers.enumerated() {
                        if let player = player, player.isPlaying {
                            let targetVolume = audioController.calculateVolumeForTrack(at: index, speed: newSpeed)
                            audioController.fadeVolume(for: player, to: targetVolume, duration: 1.0)
                        }
                    }
                }
            }
            if audioController.isSoundtrackPlaying {
                audioController.updateNowPlayingInfo()
            }
        }
        .onChange(of: showEditPage, initial: false) { _, newValue in
            print("showEditPage changed to: \(newValue)")
            if newValue {
                // Remember if the playback sheet was open before opening edit page
                wasPlaybackSheetOpenForEdit = showPlaybackPage
                print("Opening edit page, wasPlaybackSheetOpenForEdit: \(wasPlaybackSheetOpenForEdit)")
                showPlaybackPage = false
                playbackPageRemovalDirection = .leading
                withAnimation(.easeInOut(duration: 0.2)) {
                    previousPage = currentPage
                    currentPage = .edit
                }
                print("Set currentPage to .edit")
            } else {
                print("Closing edit page, wasPlaybackSheetOpenForEdit: \(wasPlaybackSheetOpenForEdit)")
                withAnimation(.easeInOut(duration: 0.2)) {
                    previousPage = .edit
                    currentPage = .main // Go to main first, then reopen sheet if needed
                    playbackPageInsertionDirection = .leading
                    playbackPageRemovalDirection = .trailing
                }
                // After the animation, reopen the playback sheet if it was open before
                if wasPlaybackSheetOpenForEdit {
                    print("Reopening playback sheet after edit page")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showPlaybackPage = true
                        wasPlaybackSheetOpenForEdit = false
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.playbackPageInsertionDirection = .trailing
                }
            }
        }
        .onChange(of: showSpeedDetailPage, initial: false) { _, newValue in
            if newValue {
                // Remember if the playback sheet was open before opening speed detail
                wasPlaybackSheetOpenForSpeedDetail = showPlaybackPage
                showPlaybackPage = false
                playbackPageRemovalDirection = .leading
                withAnimation(.easeInOut(duration: 0.2)) {
                    previousPage = currentPage
                    currentPage = .speedDetail
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    previousPage = .speedDetail
                    currentPage = .main // Go to main first, then reopen sheet if needed
                    playbackPageInsertionDirection = .leading
                    playbackPageRemovalDirection = .trailing
                }
                // After the animation, reopen the playback sheet if it was open before
                if wasPlaybackSheetOpenForSpeedDetail {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showPlaybackPage = true
                        wasPlaybackSheetOpenForSpeedDetail = false
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.playbackPageInsertionDirection = .trailing
                }
            }
        }
        .onChange(of: showSettingsPage, initial: false) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                if newValue {
                    previousPage = currentPage
                    currentPage = .settings
                } else {
                    currentPage = .speedDetail
                }
            }
        }
        .onChange(of: currentPage) { oldPage, newPage in
            print("currentPage changed from \(oldPage) to \(newPage)")
            // Update AppDelegate with current page for orientation control
            AppDelegate.currentPage = newPage
            
            // Handle transition from uploading to aiConfigure
            if oldPage == .uploading && newPage == .aiConfigure {
                print("[ContentView] Transitioning from uploading to aiConfigure, hiding uploading screen")
                withAnimation(.easeInOut(duration: 0.2)) {
                    showUploading = false
                    isUploading = false
                    isDownloading = false
                }
            }
            
            // Debug: Log all page transitions
            print("[ContentView] Page transition: \(oldPage) -> \(newPage)")
            
            if newPage == .playback || newPage == .settings {
                setDeviceOrientation(.portrait)
            }
            if newPage == .masterSettings {
                withAnimation(.easeInOut(duration: 0.2)) {
                    previousPage = oldPage
                }
            } else if newPage == .main && oldPage == .masterSettings {
                withAnimation(.easeInOut(duration: 0.2)) {
                    previousPage = .masterSettings
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
        .onReceive(NotificationCenter.default.publisher(for: .aiDownloadCompleted)) { notification in
            print("[ContentView] Received aiDownloadCompleted notification")
            if let downloadedTracks = notification.object as? [SeparatedTrack] {
                print("[ContentView] Download completed with \(downloadedTracks.count) tracks")
                
                // Set up the tracks for the AI Configure page
                setupAITracks(downloadedTracks: downloadedTracks)
                
                // If we're currently on the uploading page, navigate to AI Configure
                if currentPage == .uploading {
                    print("[ContentView] Currently on uploading page, navigating to aiConfigure")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showUploading = false
                        isUploading = false
                        isDownloading = false
                        currentPage = .aiConfigure
                    }
                }
            }
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
            .presentationDetents([.height(100), .height(150), .large], selection: .constant(.large))
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
    
    // MARK: - Volume Page
    private var volumeScreen: some View {
        VolumeScreen( 
            showVolumePage: $showVolumePage,
            volumePageSource: $volumePageSource,
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
        .environmentObject(audioController)
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
            selectedCardColor: $selectedCardColor,
            handleDoneAction: handleDoneAction
        )
    }
    
    // MARK: AI Configure Page
    private var aiConfigureScreen: some View {
        AIConfigurePage(
            showAIConfigurePage: Binding(
                get: { currentPage == .aiConfigure },
                set: { show in if (!show) { currentPage = .main } }
            ),
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
            selectedCardColor: $selectedCardColor,
            handleDoneAction: handleDoneAction
        )
    }
    

    
    
    // MARK: Speed Detail Components
    private func landscapeLinearGauge(geometry: GeometryProxy) -> some View {
        let scaledSpeed = animatedSpeed // Remove min(animatedSpeed, 100)
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
                        Gauge(value: scaledSpeed, in: 0...180) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("0")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        } maximumValueLabel: {
                            Text("180")
                                .font(.system(size: 16, design: gaugeFontStyle == "rounded" ? .rounded : .default))
                                .foregroundColor(.white)
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .frame(width: geometry.size.width * 0.2, height: 8)
                        .scaleEffect(4.0)
                    } else {
                        Gauge(value: scaledSpeed, in: 0...180) {
                            EmptyView()
                        }
                        .gaugeStyle(.linearCapacity)
                        .frame(width: geometry.size.width * 0.2, height: 8)
                        .scaleEffect(4.0)
                    }
                } else {
                    Gauge(value: scaledSpeed, in: 0...180) {
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
                            Text("180")
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
        let scaledSpeed = animatedSpeed // Remove min(animatedSpeed, 100)
        return ZStack {
            Gauge(value: scaledSpeed, in: 0...180) {
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
                    Text("180")
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
        let scaledSpeed = animatedSpeed // Remove min(animatedSpeed, 100)
        return Group {
            if portraitGaugeStyle == "fullCircle" {
                ZStack {
                    Gauge(value: scaledSpeed, in: 0...180) {
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
                    Gauge(value: scaledSpeed, in: 0...180) {
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
                            Text("180")
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSpeedDetailPage = false
                            }
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .globalButtonStyle()
                        }
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSettingsPage = true
                            }
                        }) {
                            Image(systemName: "gearshape")
                                .globalButtonStyle()
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
        PageLayout(
            title: "Settings",
            leftButtonAction: {},
            rightButtonAction: {},
            leftButtonSymbol: "",
            rightButtonSymbol: "",
            bottomButtons: [
                PageButton(label: {
                    Image(systemName: "arrow.uturn.backward").globalButtonStyle()
                }, action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSettingsPage = false
                    }
                })
            ]
        ) {
            VStack(spacing: 40) {
                // Portrait Gauge Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("PORTRAIT GAUGE")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        Picker("Gauge Style", selection: $portraitGaugeStyle) {
                            Text("Full Circle").tag("fullCircle")
                            Text("Separated Arc").tag("separatedArc")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
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
                            .padding(.horizontal)
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
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(GlobalCardAppearance)
                }
                .padding(.horizontal)
               
                // Landscape Gauge Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("LANDSCAPE GAUGE")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        Picker("Gauge Style", selection: Binding(
                            get: { landscapeGaugeStyle },
                            set: { newValue in
                                landscapeGaugeStyle = newValue
                                if newValue == "circular" && syncCircularGaugeSettings {
                                    landscapeShowMinMax = portraitShowMinMax
                                    landscapeShowCurrentSpeed = showPortraitSpeed
                                }
                            }
                        )) {
                            Text("Line").tag("line")
                            Text("Circular").tag("circular")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        if landscapeGaugeStyle == "line" {
                            Picker("Indicator Style", selection: $landscapeIndicatorStyle) {
                                Text("Dot").tag("line")
                                Text("Fill").tag("fill")
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
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
                        .padding(.horizontal)
                        
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
                        .padding(.horizontal)
                        
                        if landscapeGaugeStyle == "line" {
                            Toggle("Show Soundtrack Title", isOn: $landscapeShowSoundtrackTitle)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                        }
                        
                        if landscapeGaugeStyle == "circular" {
                            Toggle("Sync with Portrait Settings", isOn: Binding(
                                get: { syncCircularGaugeSettings },
                                set: { newValue in
                                    syncCircularGaugeSettings = newValue
                                    if newValue {
                                        landscapeShowMinMax = portraitShowMinMax
                                        landscapeShowCurrentSpeed = showPortraitSpeed
                                    }
                                }
                            ))
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    .background(GlobalCardAppearance)
                }
                .padding(.horizontal)
                
                // General Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("GENERAL")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        Toggle("Use Black Background", isOn: $useBlackBackground)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Picker("Gauge Font Style", selection: $gaugeFontStyle) {
                            Text("Default").tag("default")
                            Text("Rounded").tag("rounded")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(GlobalCardAppearance)
                }
                .padding(.horizontal)
            }
        }
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
    
    // MARK: - AI Track Setup
    private func setupAITracks(downloadedTracks: [SeparatedTrack]) {
        print("[ContentView] Setting up AI tracks with \(downloadedTracks.count) tracks")
        
        // Debug: List all files in AI_Downloaded_Files directory
        listAIDownloadedFiles()
        
        // Set up tracks with converted compressed audio files
        setupTracksWithConvertedFiles(tracks: downloadedTracks)
    }
    
    private func listAIDownloadedFiles() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[ContentView] Failed to access documents directory")
            return
        }
        
        let aiDownloadedFilesPath = documentsDirectory.appendingPathComponent("AI_Downloaded_Files")
        print("[ContentView] Checking AI_Downloaded_Files directory: \(aiDownloadedFilesPath.path)")
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: aiDownloadedFilesPath, includingPropertiesForKeys: nil)
            print("[ContentView] Found \(contents.count) files in AI_Downloaded_Files:")
            for file in contents {
                let attrs = try? fileManager.attributesOfItem(atPath: file.path)
                let fileSize = attrs?[.size] as? UInt64 ?? 0
                print("[ContentView] - \(file.lastPathComponent) (\(fileSize) bytes)")
            }
        } catch {
            print("[ContentView] Error listing AI_Downloaded_Files: \(error)")
        }
    }
    
    private func setupTracksWithConvertedFiles(tracks: [SeparatedTrack]) {
        // Set up audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("[ContentView] Audio session configured for playback")
        } catch {
            print("[ContentView] Failed to configure audio session: \(error.localizedDescription)")
        }
        
        // Find the actual converted files in AI_Downloaded_Files directory
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let aiDownloadedFilesPath = documentsPath.appendingPathComponent("AI_Downloaded_Files")
        
        // Helper function to find the actual file for a track
        func findActualFile(for track: SeparatedTrack) -> URL? {
            // Debug: Print the track name to understand what we're looking for
            print("[ContentView] Looking for file for track: \(track.name)")
            
            // The track.name contains just the track type (e.g., "drums.wav", "bass.wav")
            // But the actual files have the full base name (e.g., "Zen Garden_drums.m4a")
            // We need to find files that end with the track type but have the full base name
            
            let possibleExtensions = [".m4a", ".mp3", ".wav"]
            let trackType = track.name.replacingOccurrences(of: ".wav", with: "")
            
            // List all files in the directory to find matching ones
            do {
                let contents = try fileManager.contentsOfDirectory(at: aiDownloadedFilesPath, includingPropertiesForKeys: nil)
                for file in contents {
                    let fileName = file.lastPathComponent
                    // Check if this file ends with our track type and has a valid extension
                    for ext in possibleExtensions {
                        let expectedSuffix = trackType + ext
                        if fileName.hasSuffix(expectedSuffix) {
                            print("[ContentView] Found actual file for \(track.name): \(fileName)")
                            return file
                        }
                    }
                }
            } catch {
                print("[ContentView] Error listing directory: \(error)")
            }
            
            print("[ContentView] Warning: No actual file found for \(track.name)")
            return nil
        }
        
        // Ensure all tracks come from the same base audio file
        guard let firstTrack = tracks.first else {
            print("[ContentView] No tracks found")
            return
        }
        
        let targetBaseName = firstTrack.baseName
        print("[ContentView] Ensuring all tracks come from base audio file: \(targetBaseName)")
        
        // Filter tracks to only include those from the same base audio file
        let sameBaseTracks = tracks.filter { $0.baseName == targetBaseName }
        print("[ContentView] Found \(sameBaseTracks.count) tracks from base audio file: \(targetBaseName)")
        
        // Organize tracks by type and find their actual files
        let drumsTrack = sameBaseTracks.first { $0.trackType == "Drums" }
        let bassTrack = sameBaseTracks.first { $0.trackType == "Bass" }
        let vocalsTrack = sameBaseTracks.first { $0.trackType == "Vocals" }
        let otherTrack = sameBaseTracks.first { $0.trackType == "Other" }
        
        // Find actual file URLs
        let drumsURL = drumsTrack.flatMap { findActualFile(for: $0) }
        let bassURL = bassTrack.flatMap { findActualFile(for: $0) }
        let vocalsURL = vocalsTrack.flatMap { findActualFile(for: $0) }
        let otherURL = otherTrack.flatMap { findActualFile(for: $0) }
        
        print("[ContentView] Organized tracks - Drums: \(drumsTrack?.name ?? "nil"), Bass: \(bassTrack?.name ?? "nil"), Vocals: \(vocalsTrack?.name ?? "nil"), Other: \(otherTrack?.name ?? "nil")")
        print("[ContentView] Actual file URLs - Drums: \(drumsURL?.path ?? "nil"), Bass: \(bassURL?.path ?? "nil"), Vocals: \(vocalsURL?.path ?? "nil"), Other: \(otherURL?.path ?? "nil")")
        
        // Set base audio (Drums)
        if let drumsURL = drumsURL {
            print("[ContentView] Setting drums as base audio: \(drumsURL)")
            createBaseAudioURL = drumsURL
            createBaseTitle = "Drums"
            
            // Create AVAudioPlayer for drums (using try? like manual picker)
            if let player = try? AVAudioPlayer(contentsOf: drumsURL) {
                player.prepareToPlay()
                player.volume = mapVolume(createBaseVolume)
                createBasePlayer = player
                print("[ContentView] Created base player for drums with duration: \(player.duration) seconds")
            } else {
                print("[ContentView] Failed to create base player for drums")
                print("[ContentView] File path: \(drumsURL.path)")
                print("[ContentView] File exists: \(FileManager.default.fileExists(atPath: drumsURL.path))")
                
                // Try to get file attributes for debugging
                if let attrs = try? FileManager.default.attributesOfItem(atPath: drumsURL.path) {
                    print("[ContentView] File size: \(attrs[.size] ?? "unknown")")
                    print("[ContentView] File type: \(attrs[.type] ?? "unknown")")
                }
            }
        }
        
        // Set up dynamic tracks
        var additionalZStacks: [ZStackData] = []
        var additionalTitles: [String] = []
        var additionalAlwaysPlaying: [Bool] = []
        
        // Track 1: Bass
        if let bassURL = bassURL {
            print("[ContentView] Adding bass as dynamic track 1: \(bassURL)")
            var bassZStack = ZStackData(id: createNextID)
            bassZStack.audioURL = bassURL
            bassZStack.player = createAudioPlayer(for: bassURL)
            bassZStack.volume = 0.0
            additionalZStacks.append(bassZStack)
            additionalTitles.append("Bass")
            additionalAlwaysPlaying.append(false)
            createNextID += 1
        }
        
        // Track 2: Vocals
        if let vocalsURL = vocalsURL {
            print("[ContentView] Adding vocals as dynamic track 2: \(vocalsURL)")
            var vocalsZStack = ZStackData(id: createNextID)
            vocalsZStack.audioURL = vocalsURL
            vocalsZStack.player = createAudioPlayer(for: vocalsURL)
            vocalsZStack.volume = 0.0
            additionalZStacks.append(vocalsZStack)
            additionalTitles.append("Vocals")
            additionalAlwaysPlaying.append(false)
            createNextID += 1
        }
        
        // Track 3: Other
        if let otherURL = otherURL {
            print("[ContentView] Adding other as dynamic track 3: \(otherURL)")
            var otherZStack = ZStackData(id: createNextID)
            otherZStack.audioURL = otherURL
            otherZStack.player = createAudioPlayer(for: otherURL)
            otherZStack.volume = 0.0
            additionalZStacks.append(otherZStack)
            additionalTitles.append("Other")
            additionalAlwaysPlaying.append(false)
            createNextID += 1
        }
        
        // Update CreatePage bindings
        createAdditionalZStacks = additionalZStacks
        createAdditionalTitles = additionalTitles
        createAdditionalAlwaysPlaying = additionalAlwaysPlaying
        
        // Set default speed ranges for dynamic tracks
        createAudio1MinimumSpeed = 0
        createAudio1MaximumSpeed = 80
        createAudio2MinimumSpeed = 0
        createAudio2MaximumSpeed = 80
        createAudio3MinimumSpeed = 0
        createAudio3MaximumSpeed = 80
        
        print("[ContentView] Successfully set up AI tracks with \(additionalZStacks.count) dynamic tracks")
        print("[ContentView] Base audio URL: \(createBaseAudioURL?.path ?? "nil")")
        print("[ContentView] Base player: \(createBasePlayer != nil ? "created" : "nil")")
        print("[ContentView] Additional ZStacks count: \(createAdditionalZStacks.count)")
        for (index, zstack) in createAdditionalZStacks.enumerated() {
            print("[ContentView] ZStack \(index): audioURL=\(zstack.audioURL?.path ?? "nil"), player=\(zstack.player != nil ? "created" : "nil")")
        }
    }
    
    private func createAudioPlayer(for url: URL) -> AVAudioPlayer? {
        print("[ContentView] Attempting to create audio player for: \(url.lastPathComponent)")
        print("[ContentView] Full path: \(url.path)")
        print("[ContentView] File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            player.volume = 1.0
            print("[ContentView] Successfully created audio player for \(url.lastPathComponent) with duration: \(player.duration) seconds")
            return player
        } else {
            print("[ContentView] Failed to create audio player for \(url.lastPathComponent)")
            print("[ContentView] File path: \(url.path)")
            print("[ContentView] File exists: \(FileManager.default.fileExists(atPath: url.path))")
            
            // Try to get file attributes for debugging
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                print("[ContentView] File size: \(attrs[.size] ?? "unknown")")
                print("[ContentView] File type: \(attrs[.type] ?? "unknown")")
            }
            
            // Try to read the file to see if it's accessible
            do {
                let data = try Data(contentsOf: url)
                print("[ContentView] File is readable, size: \(data.count) bytes")
            } catch {
                print("[ContentView] File is not readable: \(error.localizedDescription)")
            }
            
            return nil
        }
    }
    

    
    // MARK: - Persistence Functions
    func saveSoundtracks() {
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
            
            // Also create a copy in a more accessible location
            createAccessibleCopy()
        } catch {
            print("Failed to save soundtracks: \(error)")
        }
    }
    
    private func createAccessibleCopy() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        // Create a more accessible folder
        let accessibleFolder = documentsDirectory.appendingPathComponent("Dynamidrive_Accessible")
        do {
            if !fileManager.fileExists(atPath: accessibleFolder.path) {
                try fileManager.createDirectory(at: accessibleFolder, withIntermediateDirectories: true)
                print("[ContentView] Created accessible folder: \(accessibleFolder)")
            }
            
            // Copy soundtracks.json to accessible location
            let sourceURL = documentsDirectory.appendingPathComponent("soundtracks.json")
            let destURL = accessibleFolder.appendingPathComponent("soundtracks.json")
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: destURL)
                print("[ContentView] Copied soundtracks.json to accessible location")
            }
            
            // Create a README file with instructions
            let readmeURL = accessibleFolder.appendingPathComponent("README.txt")
            let readmeContent = """
Dynamidrive App - Accessible Files
==================================

This folder contains accessible copies of Dynamidrive app files.

Created on: \(Date())

Files:
- soundtracks.json: Soundtrack metadata

To find this folder:
1. Open Files app
2. Go to "On My iPhone/iPad" 
3. Look for "Dynamidrive" folder
4. Inside should be "Dynamidrive_Accessible" folder

If you can't see it, the app may not have permission to create visible folders.
Check the console output for the exact file paths.
"""
            try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
            print("[ContentView] Created README.txt in accessible folder")
            
        } catch {
            print("[ContentView] Error creating accessible copy: \(error)")
        }
    }
    
    private func loadSoundtracks() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to access documents directory for loading soundtracks")
            return
        }
        
        // Debug: List all files in Documents directory
        print("[ContentView] === LISTING ALL FILES IN DOCUMENTS DIRECTORY ===")
        do {
            let contents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            print("[ContentView] Documents directory: \(documentsDirectory.path)")
            print("[ContentView] All files in Documents directory:")
            for file in contents {
                if let attrs = try? fileManager.attributesOfItem(atPath: file.path), let fileSize = attrs[.size] as? UInt64 {
                    print("  - \(file.lastPathComponent) (\(fileSize) bytes)")
                } else {
                    print("  - \(file.lastPathComponent)")
                }
            }
        } catch {
            print("[ContentView] Error listing Documents directory: \(error)")
        }
        print("[ContentView] === END OF FILE LISTING ===")
        
        let fileURL = documentsDirectory.appendingPathComponent("soundtracks.json")
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
                                                  players: players,
                                                  cardColor: loadedSoundtracks[i].cardColor,
                                                  isAI: loadedSoundtracks[i].isAI)
            }
            
            soundtracks = loadedSoundtracks
            print("Loaded \(loadedSoundtracks.count) soundtracks from \(fileURL.path)")
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
            if audioController.isSoundtrackPlaying {
                audioController.toggleSoundtrackPlayback()
            }
            // Removed pauseAllAudio() here to allow multiple preview tracks
            // Reset playback position if nothing else is playing
            let isAnyPlaying = createAdditionalZStacks.contains(where: { $0.isPlaying })
            if !isAnyPlaying {
                audioController.masterPlaybackTime = 0
            } else if let firstPlayingPlayer = getFirstPlayingPlayer(), firstPlayingPlayer.isPlaying {
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
            if audioController.isSoundtrackPlaying {
                audioController.toggleSoundtrackPlayback()
            }
            // Removed pauseAllAudio() here to allow multiple preview tracks
            // Reset playback position if nothing else is playing
            let isAnyPlaying = createBaseIsPlaying || createAdditionalZStacks.contains(where: { $0.isPlaying && $0.id != createAdditionalZStacks[index].id })
            if !isAnyPlaying {
                audioController.masterPlaybackTime = 0
            } else if let firstPlayingPlayer = getFirstPlayingPlayer(), firstPlayingPlayer.isPlaying {
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
    
    private func cleanupWAVFiles() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[ContentView] Failed to access documents directory for cleanup")
            return
        }
        
        let aiDownloadedFilesPath = documentsDirectory.appendingPathComponent("AI_Downloaded_Files")
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: aiDownloadedFilesPath, includingPropertiesForKeys: nil)
            var deletedCount = 0
            
            for file in contents {
                let fileName = file.lastPathComponent
                // Delete all files in the AI_Downloaded_Files directory
                try fileManager.removeItem(at: file)
                print("[ContentView] Cleaned up file: \(fileName)")
                deletedCount += 1
            }
            
            print("[ContentView] Cleanup completed: deleted \(deletedCount) files from AI_Downloaded_Files")
        } catch {
            print("[ContentView] Error during cleanup: \(error)")
        }
    }
    
    private func deleteSoundtrack(_ soundtrack: Soundtrack) {
        // Ensure there is at least one track before attempting to access it
        guard let firstTrack = soundtrack.tracks.first else {
            print("No tracks found for soundtrack: \(soundtrack.title)")
            soundtracks.removeAll { $0.id == soundtrack.id }
            if audioController.currentSoundtrackTitle == soundtrack.title {
                audioController.setCurrentSoundtrack(id: soundtrack.id, tracks: [], players: [], title: "")
            }
            saveSoundtracks()
            return
        }
        
        let audioURL = documentsDirectory.appendingPathComponent(firstTrack.audioFileName)
        removeAudioFile(at: audioURL)
        
        soundtracks.removeAll { $0.id == soundtrack.id }
        
        if audioController.currentSoundtrackTitle == soundtrack.title {
            audioController.setCurrentSoundtrack(id: soundtrack.id, tracks: [], players: [], title: "")
        }
        
        print("Deleted soundtrack: \(soundtrack.title)")
        saveSoundtracks() // Save the updated soundtracks
    }
    
    private func handleDoneAction() {
        print("=== handleDoneAction CALLED ===")
        print("[ContentView] handleDoneAction called")
        let successHaptic = UINotificationFeedbackGenerator()
        successHaptic.notificationOccurred(.success)
        var tracks: [AudioController.SoundtrackData] = []
        
        if let baseURL = createBaseAudioURL {
            print("[ContentView] Adding base track: \(baseURL.lastPathComponent)")
            tracks.append(AudioController.SoundtrackData(
                audioFileName: baseURL.lastPathComponent,
                displayName: createBaseTitle,
                maximumVolume: createBaseVolume,
                minimumSpeed: 0,
                maximumSpeed: 0
            ))
        } else {
            print("[ContentView] No base audio URL found")
        }
        
        for (index, zStack) in createAdditionalZStacks.enumerated() {
            if let audioURL = zStack.audioURL {
                print("[ContentView] Adding additional track \(index): \(audioURL.lastPathComponent)")
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
            } else {
                print("[ContentView] Additional track \(index) has no audio URL")
            }
        }
        
        print("[ContentView] Creating players for \(tracks.count) tracks")
        print("[ContentView] Tracks to create players for:")
        for (index, track) in tracks.enumerated() {
            print("[ContentView] Track \(index): \(track.displayName) - \(track.audioFileName)")
        }
        let players = tracks.map { track in
            let fileManager = FileManager.default
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("[ContentView] Failed to access documents directory")
                return nil as AVAudioPlayer?
            }
            
            // Check if this is an AI separated track (stored in AI_Downloaded_Files)
            let aiDownloadedFilesPath = documentsDirectory.appendingPathComponent("AI_Downloaded_Files")
            
            // For AI separated tracks, try different file extensions (.m4a, .mp3, .wav)
            // The track.audioFileName already contains the full filename, so we need to handle it properly
            var audioURL: URL?
            
            // First, try to find the exact file in AI_Downloaded_Files directory
            let exactFileURL = aiDownloadedFilesPath.appendingPathComponent(track.audioFileName)
            if fileManager.fileExists(atPath: exactFileURL.path) {
                audioURL = exactFileURL
                print("[ContentView] Using AI separated track (exact match): \(exactFileURL.path)")
            } else {
                // If exact match not found, try different extensions
                let baseName = track.audioFileName.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".m4a", with: "").replacingOccurrences(of: ".wav", with: "")
                let possibleExtensions = [".m4a", ".mp3", ".wav"]
                
                for ext in possibleExtensions {
                    let testFileName = baseName + ext
                    let testURL = aiDownloadedFilesPath.appendingPathComponent(testFileName)
                    if fileManager.fileExists(atPath: testURL.path) {
                        audioURL = testURL
                        print("[ContentView] Using AI separated track (extension match): \(testURL.path)")
                        break
                    }
                }
            }
            
            // If not found in AI_Downloaded_Files, try the main documents directory
            if audioURL == nil {
                audioURL = documentsDirectory.appendingPathComponent(track.audioFileName)
                print("[ContentView] Using regular track: \(audioURL!.path)")
            }
            
            // Ensure we have a valid URL
            guard let finalAudioURL = audioURL else {
                print("[ContentView] No valid audio URL found for \(track.audioFileName)")
                return nil as AVAudioPlayer?
            }
            
            // Debug: Check file details
            print("[ContentView] Attempting to create player for: \(track.audioFileName)")
            print("[ContentView] Full URL: \(finalAudioURL.path)")
            print("[ContentView] File exists: \(fileManager.fileExists(atPath: finalAudioURL.path))")
            
            if let attrs = try? fileManager.attributesOfItem(atPath: finalAudioURL.path) {
                print("[ContentView] File size: \(attrs[.size] ?? "unknown") bytes")
            }
            
            do {
                let player = try AVAudioPlayer(contentsOf: finalAudioURL)
                player.volume = mapVolume(track.maximumVolume)
                player.prepareToPlay()
                print("[ContentView] Successfully created player for \(track.audioFileName) with duration: \(player.duration) seconds")
                return player
            } catch {
                print("[ContentView] Failed to create AVAudioPlayer for \(track.audioFileName): \(error)")
                print("[ContentView] Attempted URL: \(finalAudioURL.path)")
                print("[ContentView] File exists: \(fileManager.fileExists(atPath: finalAudioURL.path))")
                
                // Try to read the file to see if it's accessible
                do {
                    let data = try Data(contentsOf: finalAudioURL)
                    print("[ContentView] File is readable, size: \(data.count) bytes")
                    
                    // Check file header to see what format it actually is
                    let header = data.prefix(16)
                    print("[ContentView] File header (hex): \(header.map { String(format: "%02x", $0) }.joined())")
                    
                    // Check if it's M4A (should start with 'ftyp')
                    if header.count >= 4 && String(data: header.prefix(4), encoding: .ascii) == "ftyp" {
                        print("[ContentView] File is M4A format")
                    } else {
                        print("[ContentView] File format unknown")
                    }
                } catch {
                    print("[ContentView] File is not readable: \(error.localizedDescription)")
                }
                
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
        
        // Debug: Print track and player information
        print("[ContentView] Creating soundtrack with \(tracks.count) tracks:")
        for (index, track) in tracks.enumerated() {
            print("[ContentView] Track \(index): \(track.displayName) - \(track.audioFileName)")
            if index < players.count {
                print("[ContentView] Player \(index): \(players[index] != nil ? "created" : "nil")")
                if let player = players[index] {
                    print("[ContentView] Player \(index) duration: \(player.duration) seconds")
                }
            }
        }
        
        // Debug: Check if any players were created
        let validPlayers = players.compactMap { $0 }
        print("[ContentView] Valid players count: \(validPlayers.count) out of \(players.count)")
        
        // Determine if this is an AI soundtrack by checking if files are in AI_Downloaded_Files directory
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[ContentView] Failed to access documents directory")
            return
        }
        
        let aiDownloadedFilesPath = documentsDirectory.appendingPathComponent("AI_Downloaded_Files")
        
        // Check if any tracks are from AI_Downloaded_Files directory
        var isAISoundtrack = false
        for track in tracks {
            let aiFileURL = aiDownloadedFilesPath.appendingPathComponent(track.audioFileName)
            if fileManager.fileExists(atPath: aiFileURL.path) {
                isAISoundtrack = true
                break
            }
        }
        
        if isAISoundtrack {
            // For AI soundtracks, copy files to main documents directory before cleanup
            print("[ContentView] Detected AI soundtrack, copying files to main directory")
            
            // Copy AI files to main documents directory and update track filenames
            var updatedTracks: [AudioController.SoundtrackData] = []
            for track in tracks {
                let sourceURL = aiDownloadedFilesPath.appendingPathComponent(track.audioFileName)
                let destURL = documentsDirectory.appendingPathComponent(track.audioFileName)
                
                if fileManager.fileExists(atPath: sourceURL.path) {
                    do {
                        // Remove existing file if it exists
                        if fileManager.fileExists(atPath: destURL.path) {
                            try fileManager.removeItem(at: destURL)
                        }
                        // Copy file to main documents directory
                        try fileManager.copyItem(at: sourceURL, to: destURL)
                        print("[ContentView] Copied AI file: \(track.audioFileName) to main documents directory")
                        updatedTracks.append(track)
                    } catch {
                        print("[ContentView] Failed to copy AI file \(track.audioFileName): \(error)")
                        // Keep original track if copy fails
                        updatedTracks.append(track)
                    }
                } else {
                    print("[ContentView] AI file not found: \(track.audioFileName)")
                    // Keep original track if file not found
                    updatedTracks.append(track)
                }
            }
            
            // Create soundtrack with updated tracks
            soundtracks.append(Soundtrack(id: UUID(), title: newTitle, tracks: updatedTracks, players: players, cardColor: selectedCardColor, isAI: true))
        } else {
            // Append the new soundtrack with the unique title (for non-AI soundtracks)
            print("[ContentView] Creating manual soundtrack")
            soundtracks.append(Soundtrack(id: UUID(), title: newTitle, tracks: tracks, players: players, cardColor: selectedCardColor, isAI: false))
        }
        
        pauseAllAudio()
        
        // Clean up WAV files from AI_Downloaded_Files directory
        cleanupWAVFiles()
        
        // Reset state before animation
        resetCreatePage()
        selectedCardColor = .clear // Reset color selection
        
        // Navigate back to mainScreen
        withAnimation(.easeInOut(duration: 0.2)) {
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
                players: players,
                cardColor: .clear,
                isAI: false
            )
            
            soundtracks.append(newSoundtrack)
            saveSoundtracks()
            
            // Reset states and navigate to main page
            withAnimation(.easeInOut(duration: 0.2)) {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            previousPage = .import
                            currentPage = .create
                        }
                    }) {
                        Image(systemName: "arrow.uturn.backward")
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
    private var aiUpload: some View {
        AIUploadPage(
            onBack: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentPage = .create // Go back to the create page
                }
            },
            showCreatePage: $showCreatePage,
            showConfigurePage: $showConfigurePage,
            createBaseAudioURL: $createBaseAudioURL,
            createBasePlayer: $createBasePlayer,
            createBaseIsPlaying: $createBaseIsPlaying,
            createBaseOffset: $createBaseOffset,
            createBaseShowingFilePicker: $createBaseShowingFilePicker,
            createBaseVolume: $createBaseVolume,
            createAdditionalZStacks: $createAdditionalZStacks,
            createAdditionalTitles: $createAdditionalTitles,
            createAdditionalAlwaysPlaying: $createAdditionalAlwaysPlaying,
            createBaseTitle: $createBaseTitle,
            createSoundtrackTitle: $createSoundtrackTitle,
            createReferenceLength: $createReferenceLength,
            createNextID: $createNextID,
            currentPage: $currentPage,
            showUploading: $showUploading,
            isUploading: $isUploading,
            isDownloading: $isDownloading,
            soundtracks: $soundtracks,
            createAudio1MinimumSpeed: $createAudio1MinimumSpeed,
            createAudio1MaximumSpeed: $createAudio1MaximumSpeed,
            createAudio2MinimumSpeed: $createAudio2MinimumSpeed,
            createAudio2MaximumSpeed: $createAudio2MaximumSpeed,
            createAudio3MinimumSpeed: $createAudio3MinimumSpeed,
            createAudio3MaximumSpeed: $createAudio3MaximumSpeed,
            createAudio4MinimumSpeed: $createAudio4MinimumSpeed,
            createAudio4MaximumSpeed: $createAudio4MaximumSpeed,
            createAudio5MinimumSpeed: $createAudio5MinimumSpeed,
            createAudio5MaximumSpeed: $createAudio5MaximumSpeed
        )
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

// MARK: - Document Pickers
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.zip], asCopy: true)
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

struct AudioDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio, UTType.mp3, UTType.wav], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: AudioDocumentPicker
        
        init(_ parent: AudioDocumentPicker) {
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
    @AppStorage("locationTrackingEnabled") private var locationTrackingEnabled: Bool = true
    @AppStorage("hasGrantedLocationPermission") private var hasGrantedLocationPermission = false
    private var lastLocation: CLLocation?
    private var isTrackingDistance: Bool = false
    private let locationManager = CLLocationManager()
    private var currentSoundtrackID: UUID?
    var isSpeedUpdatesPaused: Bool = false // <--- Add this
    
    // Per-soundtrack distance storage
    @Published var soundtrackDistances: [UUID: Double] = [:] // miles
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        loadDistances()
    }
    
    func startDistanceTracking(for soundtrackID: UUID?) {
        isTrackingDistance = true
        lastLocation = location
        currentSoundtrackID = soundtrackID
    }
    
    func stopDistanceTracking() {
        isTrackingDistance = false
        lastLocation = nil
        currentSoundtrackID = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            speedMPH = 0.0
            status = "No location data"
            print("No location data received")
            return
        }
        self.location = location
        if isSpeedUpdatesPaused {
            // Don't update speed or trigger volume logic
            return
        }
        let speed = max(location.speed, 0)
        speedMPH = speed * 2.23694 // Remove min(..., 80) to allow speeds above 80
        
        // Calculate distance if tracking is enabled and locationTrackingEnabled is true
        if isTrackingDistance && locationTrackingEnabled, let soundtrackID = currentSoundtrackID {
            if let lastLoc = lastLocation {
                let distanceInMeters = location.distance(from: lastLoc)
                let distanceInMiles = distanceInMeters / 1609.34  // Convert meters to miles
                let prev = soundtrackDistances[soundtrackID] ?? 0.0
                soundtrackDistances[soundtrackID] = prev + distanceInMiles
                saveDistances()
            }
            lastLocation = location
        }
        
        status = "Lat: \(location.coordinate.latitude), Lon: \(location.coordinate.longitude), Speed: \(String(format: "%.1f", speedMPH)) mph"
        print("Location update: Speed = \(String(format: "%.1f", speedMPH)) mph, Status = \(status)")
        
        if let audioController = (UIApplication.shared.delegate as? AppDelegate)?.audioController {
            audioController.adjustVolumesForSpeed(speedMPH)
        }
    }
    
    // Persistence for per-soundtrack distances
    private let distancesKey = "soundtrackDistances"
    private func saveDistances() {
        let dict = soundtrackDistances.mapValues { $0 }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: distancesKey)
        }
    }
    private func loadDistances() {
        if let data = UserDefaults.standard.data(forKey: distancesKey),
           let dict = try? JSONDecoder().decode([UUID: Double].self, from: data) {
            soundtrackDistances = dict
        }
    }
    func resetAllDistanceData() {
        soundtrackDistances = [:]
        saveDistances()
        lastLocation = nil
    }
    
    func startLocationUpdates() {
        // Don't start location updates if permission hasn't been granted through welcome screen
        if !hasGrantedLocationPermission {
            return
        }
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
    
    // Add this method to sync permission state
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            hasGrantedLocationPermission = true
        } else {
            hasGrantedLocationPermission = false
        }
    }
    
    func pauseSpeedUpdates() {
        isSpeedUpdatesPaused = true
        speedMPH = 0.0
    }
    
    func resumeSpeedUpdates() {
        isSpeedUpdatesPaused = false
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

// MARK: - Color Codable Extension
extension Color: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let opacity = try container.decode(Double.self, forKey: .opacity)
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        try container.encode(Double(red), forKey: .red)
        try container.encode(Double(green), forKey: .green)
        try container.encode(Double(blue), forKey: .blue)
        try container.encode(Double(alpha), forKey: .opacity)
    }
    
    private enum CodingKeys: String, CodingKey {
        case red, green, blue, opacity
    }
}


