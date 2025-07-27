import SwiftUI

extension View {
    func applyPokedexStyling(title: String) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.pixel17)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Color.pokedexRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.darkGrey)
    }

    func fadeIn<Value: Equatable>(when value: Value, duration: Double = 0.4) -> some View {
        modifier(FadeInOnValueChangeModifier(value: value, duration: duration))
    }
}

// MARK: - View Modifiers
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

struct FadeInOnValueChangeModifier<Value: Equatable>: ViewModifier {
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
