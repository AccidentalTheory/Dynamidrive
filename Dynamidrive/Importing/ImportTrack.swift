import Foundation
import AVFoundation

struct ImportTrack: Identifiable {
    let id = UUID()
    let displayName: String
    let fileURL: URL
    let minSpeed: Int
    let maxSpeed: Int
    let volume: Float
    var player: AVAudioPlayer? = nil
} 