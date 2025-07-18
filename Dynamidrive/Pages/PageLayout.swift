import SwiftUI

// Consistent layout constants for all pages
enum PageLayoutConstants {
    static let cardHorizontalPadding: CGFloat = 8
}

//MARK: Cards
let GlobalCardAppearance: AnyView = AnyView(
    Rectangle()
        .fill(.clear)
        .cornerRadius(20)
        .glassEffect(.regular.tint(.clear).interactive(),in: .rect(cornerRadius: 20.0))
)

// Mark: Buttons
struct GlobalButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 20))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(Color.white.opacity(0.2))
            .clipShape(Circle())
            .glassEffect(.regular.tint(.clear).interactive())
    }
}

// Usage: .globalButtonStyle()
extension View {
    func globalButtonStyle() -> some View {
        self.modifier(GlobalButtonModifier())
    }
}

// Minus
struct MinusButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 20))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .glassEffect(.regular.tint(.clear).interactive())
    }
}

// Usage: .MinusButtonStyle()
extension View {
    func MinusButtonStyle() -> some View {
        self.modifier(MinusButton())
    }
}

// MainScreen Soundtrack Buttons (no Glass on Glass)
struct CardButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 20))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .glassEffect(.regular.tint(.clear).interactive())
    }
}

// Usage: .CardButtonStyle()
extension View {
    func CardButtonStyle() -> some View {
        self.modifier(CardButton())
    }
}

// MARK: - Reusable HeaderView
struct HeaderView: View {
    var title: String
    var leftButtonAction: (() -> Void)? = nil
    var rightButtonAction: (() -> Void)? = nil
    var leftButtonSymbol: String? = nil
    var rightButtonSymbol: String? = nil
    
    var body: some View {
        HStack {
            if let leftButtonSymbol = leftButtonSymbol, let leftButtonAction = leftButtonAction {
                Button(action: leftButtonAction) {
                    Image(systemName: leftButtonSymbol)
                        .globalButtonStyle()
                }
            } else {
                Spacer().frame(width: 50) // Placeholder for alignment
            }
            Spacer()
            Text(title)
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            Spacer()
            if let rightButtonSymbol = rightButtonSymbol, let rightButtonAction = rightButtonAction {
                Button(action: rightButtonAction) {
                    Image(systemName: rightButtonSymbol)
                        .globalButtonStyle()
                }
            } else {
                Spacer().frame(width: 50) // Placeholder for alignment
            }
        }
        .padding(.horizontal)
        .padding(.top, UIScreen.main.bounds.height * 0.01)
    }
}

// MARK: - PageButton for bottom bar
struct PageButton: Identifiable {
    let id = UUID()
    let label: AnyView
    let action: () -> Void
    let isMenu: Bool
    
    init<Label: View>(@ViewBuilder label: () -> Label, action: @escaping () -> Void, isMenu: Bool = false) {
        self.label = AnyView(label())
        self.action = action
        self.isMenu = isMenu
    }
}

// MARK: - PageLayout
struct PageLayout<Content: View>: View {
    let title: String
    let leftButtonAction: () -> Void
    let rightButtonAction: () -> Void
    let leftButtonSymbol: String
    let rightButtonSymbol: String
    let bottomButtons: [PageButton]
    let verticalPadding: CGFloat
    let useCustomFont: Bool
    let content: () -> Content
    
    @State private var isScrolled = false
    @State private var isAtBottom = false
    
    let buttonWidth: CGFloat = 50
    let buttonSpacing: CGFloat = 89
    let buttonSlotCount: Int = 3
    var totalButtonBarWidth: CGFloat {
        CGFloat(buttonSlotCount) * buttonWidth + CGFloat(buttonSlotCount - 1) * buttonSpacing
    }
    var horizontalPadding: CGFloat {
        max((UIScreen.main.bounds.width - totalButtonBarWidth) / 2, 0)
    }
    
    init(
        title: String,
        leftButtonAction: @escaping () -> Void = {},
        rightButtonAction: @escaping () -> Void = {},
        leftButtonSymbol: String = "",
        rightButtonSymbol: String = "",
        bottomButtons: [PageButton] = [],
        verticalPadding: CGFloat = 80,
        useCustomFont: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.leftButtonAction = leftButtonAction
        self.rightButtonAction = rightButtonAction
        self.leftButtonSymbol = leftButtonSymbol
        self.rightButtonSymbol = rightButtonSymbol
        self.bottomButtons = Array(bottomButtons.prefix(3))
        self.verticalPadding = verticalPadding
        self.useCustomFont = useCustomFont
        self.content = content
    }
    
    var body: some View {
        ZStack {
            // Main stack as background, fills the page
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    GeometryReader { geo in
                        Color.clear
                            .frame(height: 0)
                            .onChange(of: geo.frame(in: .named("scroll")).minY) { value in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isScrolled = value < -8
                                }
                            }
                    }
                    .frame(height: 0)
                    content()
                    // Bottom scroll detection
                    GeometryReader { geo in
                        Color.clear
                            .frame(height: 0)
                            .onChange(of: geo.frame(in: .named("scroll")).maxY) { value in
                                let screenHeight = UIScreen.main.bounds.height
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    let bottomPadding: CGFloat = 80
                                    isAtBottom = value <= screenHeight - bottomPadding + 8
                                }
                            }
                    }
                    .frame(height: 0)
                }
                .padding(.vertical, verticalPadding)
            }
            .coordinateSpace(name: "scroll")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Top gradient overlay, only visible when scrolled
            VStack {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.black.opacity(0.6), location: 0.0),
                        .init(color: Color.black.opacity(0.6), location: 0.35),
                        .init(color: Color.clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .opacity(isScrolled ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isScrolled)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            // Bottom gradient overlay, only visible when not at bottom
            VStack {
                Spacer()
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.black.opacity(0.6), location: 0.65),
                            .init(color: Color.black.opacity(0.6), location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 220)
                    .ignoresSafeArea(edges: .bottom)
                    .opacity(!isAtBottom ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isAtBottom)
                    .allowsHitTesting(false)
                    // Bottom buttons always visible, on top of the gradient
                    HStack(spacing: buttonSpacing) {
                        if bottomButtons.count == 1 {
                            // [empty, button, empty]
                            Color.clear.frame(width: buttonWidth, height: buttonWidth)
                            if bottomButtons[0].isMenu {
                                bottomButtons[0].label
                            } else {
                                Button(action: bottomButtons[0].action) {
                                    bottomButtons[0].label
                                }
                            }
                            Color.clear.frame(width: buttonWidth, height: buttonWidth)
                        } else if bottomButtons.count == 2 {
                            // [button1, empty, button2]
                            if bottomButtons[0].isMenu {
                                bottomButtons[0].label
                            } else {
                                Button(action: bottomButtons[0].action) {
                                    bottomButtons[0].label
                                }
                            }
                            Color.clear.frame(width: buttonWidth, height: buttonWidth)
                            if bottomButtons[1].isMenu {
                                bottomButtons[1].label
                            } else {
                                Button(action: bottomButtons[1].action) {
                                    bottomButtons[1].label
                                }
                            }
                        } else {
                            // 3 or 0 buttons: default behavior
                            ForEach(0..<buttonSlotCount, id: \.self) { idx in
                                if idx < bottomButtons.count {
                                    let button = bottomButtons[idx]
                                    if button.isMenu {
                                        button.label
                                    } else {
                                        Button(action: button.action) {
                                            button.label
                                        }
                                    }
                                } else {
                                    Color.clear
                                        .frame(width: buttonWidth, height: buttonWidth)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                    .padding(.horizontal, horizontalPadding)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            // Header on top
            VStack {
                // Custom header bar with 3 slots, center is invisible button, text overlays center
                ZStack {
                    HStack(spacing: buttonSpacing) {
                        // Left button
                        if !leftButtonSymbol.isEmpty {
                            Button(action: leftButtonAction) {
                                Image(systemName: leftButtonSymbol)
                                    .globalButtonStyle()
                            }
                        } else {
                            Spacer().frame(width: buttonWidth)
                        }
                        // Center invisible button
                        Button(action: {}) {
                            Color.clear
                                .frame(width: buttonWidth, height: buttonWidth)
                        }
                        .disabled(true)
                        .opacity(0)
                        // Right button
                        if !rightButtonSymbol.isEmpty {
                            Button(action: rightButtonAction) {
                                Image(systemName: rightButtonSymbol)
                                    .globalButtonStyle()
                            }
                        } else {
                            Spacer().frame(width: buttonWidth)
                        }
                    }
                    // Title overlays center
                    Text(title)
                        .font(useCustomFont ? .ppNeueMachina(size: 25) : .system(size: 25, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, UIScreen.main.bounds.height * 0.01)
                Spacer()
            }
            // Remove floating back button overlay (now handled in bottom bar)
        }
        .zIndex(4)
    }
} 
