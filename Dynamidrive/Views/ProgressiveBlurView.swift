import SwiftUI

struct ProgressiveBlurView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .clear, location: 1)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
}

#Preview {
    ZStack {
        Color.blue
        ProgressiveBlurView()
            .frame(height: 100)
    }
} 