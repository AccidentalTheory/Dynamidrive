import SwiftUI
import AVFoundation

public struct ZStackData: Identifiable {
    public let id: Int
    public var audioURL: URL?
    public var player: AVAudioPlayer?
    public var isPlaying: Bool = false
    public var offset: CGFloat = 0
    public var volume: Float = 0.0
    
    public init(id: Int) {
        self.id = id
    }
} 