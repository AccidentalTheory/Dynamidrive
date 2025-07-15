import SwiftUI

struct EditPage: View {
    @Binding var showEditPage: Bool
    
    var body: some View {
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
                Image(systemName: "arrow.uturn.backward")
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
} 