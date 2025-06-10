import SwiftUI

struct LoadingScreen: View {
    @Binding var isLoading: Bool
    @Binding var isSpinning: Bool
    @Binding var currentPage: AppPage
    
    var body: some View {
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
} 