import SwiftUI

//MARK: Cards

  let GlobalCardAppearance: AnyView = AnyView(
      Rectangle()
          .fill(.clear)
      //    .background(.ultraThinMaterial)
       //   .overlay(Color.black.opacity(0.3))
     //     .blur(radius: 10)
          .cornerRadius(16)
          .glassEffect(in: .rect(cornerRadius: 16.0))
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
            .glassEffect(.regular.tint(.red).interactive())
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
         //   .glassEffect(.regular.tint(.red).interactive())
    }
}

// Usage: .MinusButtonStyle()
extension View {
    func CardButtonStyle() -> some View {
        self.modifier(CardButton())
    }
}

//MARK: Liquid Glass Elements. NOTE: use this as a modifier, don't recreate!

// .glassEffect(.regular.tint(.clear).interactive())


//Button(action: {
// ACTION
//})
//{
//    Image(systemName: "SF SYMBOL")
//        .font(.system(size: 20))
//        .foregroundColor(.white)
//        .frame(width: 50, height: 50)
//        .glassEffect(.regular.tint(.COLOR).interactive())
//}

// MARK: Extras

// Card Backgrounds Without glass effect

//  let GlobalCardAppearance: AnyView = AnyView(
//      Rectangle()
//          .fill(.clear)
//          .background(.ultraThinMaterial)
//          .overlay(Color.black.opacity(0.5))
//
        
//  )


