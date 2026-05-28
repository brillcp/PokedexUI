import SwiftUI

/// Sprite-over-name grid cell used in search, bookmarks, type lists, and
/// opponent picker grids.
struct PokemonSpriteCard: View, Equatable {
    let pokemon: Pokemon

    var body: some View {
        VStack(spacing: 12) {
            SpriteImage(url: pokemon.frontSprite)
                .frame(height: 92)
            Text(pokemon.name)
                .font(.pixel12)
                .lineLimit(1)
            HStack {
                ForEach(pokemon.types) { type in
                    Chip.type(type)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .foregroundStyle(.white)
    }
}
