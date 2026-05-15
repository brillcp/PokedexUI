import SwiftUI
import SwiftData

/// Bookmarks tab. Backed by `PokemonSummary` (the lightweight row that powers
/// the pokedex grid); tapping a bookmark navigates to `PokemonDetailView`,
/// which lazy-hydrates the full pokemon on appear.
struct BookmarksView: View {
    @Query(
        filter: #Predicate<PokemonSummary> { $0.isBookmarked },
        sort: \.id
    )
    private var bookmarks: [PokemonSummary]

    var body: some View {
        NavigationStack {
            if bookmarks.isEmpty {
                Text("No favourites")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .font(.pixel14)
            } else {
                PokedexGridView(pokemon: bookmarks)
            }
        }
    }
}

#Preview {
    BookmarksView()
}
