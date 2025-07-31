import SwiftUI
import SwiftData

struct BookmarksView: View {
    @Query(
        filter: #Predicate<Pokemon> { $0.isBookmarked },
        sort: \.id
    )
    private var bookmarks: [Pokemon]

    var body: some View {
        NavigationStack {
            if pokemonViewModels.isEmpty {
                Text("No favourites yet…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .font(.pixel14)
            } else {
                PokedexGridView(
                    pokemon: pokemonViewModels,
                    grid: .three
                )
            }
        }
    }
}

// MARK: - Private calculated properties
private extension BookmarksView {
    var pokemonViewModels: [PokemonViewModel] {
        bookmarks.map { PokemonViewModel(pokemon: $0) }
    }
}

#Preview {
    BookmarksView()
}
