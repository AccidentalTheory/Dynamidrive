import SwiftUI
import AVFoundation

struct ImportConfirmationPage: View {
    let soundtrackTitle: String // still required for the parent, but not shown
    let tracks: [ImportTrack]   // still required for the parent, but not shown
    let onCancel: () -> Void
    let onImport: (Color) -> Void
    
    @State private var selectedColor: Color = .clear

    var body: some View {
        PageLayout(
            title: "Import Soundtrack?",
            leftButtonAction: {},
            rightButtonAction: {},
            leftButtonSymbol: "",
            rightButtonSymbol: "",
            bottomButtons: [
                PageButton(label: {
                    Image(systemName: "multiply").globalButtonStyle()
                }, action: {
                    onCancel()
                }),
                PageButton(label: {
                    Image(systemName: "checkmark").globalButtonStyle()
                }, action: {
                    onImport(selectedColor)
                })
            ]
        ) {
            VStack(spacing: 30) {
                // Color picker section
                VStack(spacing: 15) {
                    Text("Choose Color")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(systemColors, id: \.self) { color in
                                Button(action: {
                                    selectedColor = color
                                }) {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(color == .clear ? Color.gray.opacity(0.1) : color)
                                        .frame(width: 50, height: 50)
                                        .glassEffect(.regular.tint(.clear), in: .rect(cornerRadius: 20.0))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, PageLayoutConstants.cardHorizontalPadding)
                        .padding(.vertical, 10)
                    }
                    .frame(height: 80)
                    
                    Text("All cards have a Liquid Glass material. Clear cards will reflect the color of the card above it.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .padding(.top, 20)
        }
    }
    
    // System colors excluding grays and white
    private let systemColors: [Color] = [
        .clear,
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .cyan,
        .blue,
        .indigo,
        .purple,
        .pink,
        .brown
    ]
}

// You will need to make ImportTrack accessible to this file, or move it to a shared location. 
