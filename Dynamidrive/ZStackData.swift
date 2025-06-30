import SwiftUI
import AVFoundation

struct ZStackData: Identifiable {
    let id: Int
    var audioURL: URL?
    var player: AVAudioPlayer?
    var isPlaying: Bool
    var showingFilePicker: Bool
    var offset: CGFloat
    var volume: Float
    
    init(id: Int) {
        self.id = id
        self.audioURL = nil
        self.player = nil
        self.isPlaying = false
        self.showingFilePicker = false
        self.offset = 0
        self.volume = 0.0
    }
} 