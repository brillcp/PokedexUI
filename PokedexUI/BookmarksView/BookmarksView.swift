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
            if favouriteVMs.isEmpty {
                Text("No favourites yet…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .font(.pixel14)
            } else {
                PokedexGridView(
                    pokemon: favouriteVMs,
                    grid: .three
                )
            }
        }
    }
}

// MARK: - Private calculated properties
private extension BookmarksView {
    var favouriteVMs: [PokemonViewModel] {
        bookmarks.map { PokemonViewModel(pokemon: $0) }
    }
}

#Preview {
    BookmarksView()
}
