import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    let currentSoundtrackTitle: String
    @State private var phase = 0.0
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midHeight = height / 2
                let amplitude = height / 3
                let frequency = 3.0
                
                path.move(to: CGPoint(x: 0, y: midHeight))
                
                for x in stride(from: 0, through: width, by: 1) {
                    let relativeX = x / width
                    let normalizedPhase = phase + relativeX * frequency
                    let y = midHeight + sin(normalizedPhase * 2 * .pi) * amplitude
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 2)
            .opacity(isPlaying ? 1 : 0.3)
        }
        .onReceive(timer) { _ in
            if isPlaying {
                withAnimation(.linear(duration: 0.1)) {
                    phase += 0.1
                }
            }
        }
    }
} 