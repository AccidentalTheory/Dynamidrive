import SwiftUI
import AVFoundation

struct ZStackData: Identifiable {
    let id: Int
    var audioURL: URL?
    var player: AVAudioPlayer?
    var isPlaying: Bool = false
    var showingFilePicker: Bool = false
    var offset: CGFloat = 0
    var volume: Double = 0.0
    
    init(id: Int) {
        self.id = id
    }
} 