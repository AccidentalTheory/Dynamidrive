import SwiftUI

struct GlassEffectStyle {
    let opacity: Double
    let blur: Double
    let isInteractive: Bool
    
    static let regular = GlassEffectStyle(opacity: 0.3, blur: 10, isInteractive: false)
    static let thin = GlassEffectStyle(opacity: 0.15, blur: 5, isInteractive: false)
    
    func interactive() -> GlassEffectStyle {
        GlassEffectStyle(opacity: opacity, blur: blur, isInteractive: true)
    }
}

struct GlassEffect: ViewModifier {
    let style: GlassEffectStyle
    
    func body(content: Content) -> some View {
        content
            .background {
                if style.isInteractive {
                    TransparentBlurView(style: .systemThinMaterialDark)
                        .opacity(style.opacity)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(style.opacity)
                        .blur(radius: style.blur)
                }
            }
    }
}

// UIKit blur view for interactive elements
struct TransparentBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

extension View {
    func glassEffect(_ style: GlassEffectStyle) -> some View {
        modifier(GlassEffect(style: style))
    }
}