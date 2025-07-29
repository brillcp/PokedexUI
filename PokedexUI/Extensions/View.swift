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
        modifier(FadeInViewModifier(value: value, duration: duration))
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, modify: (Self) -> Content) -> some View {
        if condition {
            modify(self)
        } else {
            self
        }
    }
}
