import SwiftUI
import SwiftData

/// Bookmarks tab. Backed by `Pokemon` rows filtered by `isBookmarked`.
/// Tapping a bookmark navigates to `PokemonDetailView`.
struct BookmarksView: View {
    @Query(
        filter: #Predicate<Pokemon> { $0.isBookmarked },
        sort: \.id
    ) private var bookmarks: [Pokemon]

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
