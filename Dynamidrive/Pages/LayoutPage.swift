import SwiftUI

struct LayoutPage: View {
    @Binding var showingLayoutPage: Bool
    
    var body: some View {
        PageLayout(
            title: "Template",
            leftButtonAction: {},
            rightButtonAction: {},
            leftButtonSymbol: "1.circle",
            rightButtonSymbol: "2.circle",
            bottomButtons: [
                PageButton(label: { Image(systemName: "arrow.uturn.backward").globalButtonStyle() }, action: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showingLayoutPage = false
                    }
                }),
                PageButton(label: { Image(systemName: "star.fill").globalButtonStyle() }, action: { print("Star tapped") }),
                PageButton(label: { Image(systemName: "heart.fill").globalButtonStyle() }, action: { print("Heart tapped") })
            ]
        ) {
            ForEach(0..<25) { index in
                PlaceholderCardView(index: index)
            }
        }
    }
}

struct PlaceholderCardView: View {
    let index: Int
    var body: some View {
        ZStack {
            GlobalCardAppearance
                .frame(height: 80)
            Text("Card \(index + 1)")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
    }
} 
