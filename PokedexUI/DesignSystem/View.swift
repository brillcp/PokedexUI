import SwiftUI

extension View {
    func applyPokedexStyling(title: String, color: Color? = Color.pokedexRed) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.pixel17)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(color ?? .red, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.darkGrey.ignoresSafeArea())
    }
}
