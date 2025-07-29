import SwiftUI

struct Perspective3D: ViewModifier {
    @Binding var isFlipped: Bool

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0)
            )
    }
}

// MARK: - Fade in modifier
struct FadeInViewModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let duration: Double

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: duration)) {
                    isVisible = true
                }
            }
            .onChange(of: value) { oldValue, newValue in
                guard newValue != oldValue else { return }
                isVisible = false
                withAnimation(.easeInOut(duration: duration)) {
                    isVisible = true
                }
            }
    }
}
