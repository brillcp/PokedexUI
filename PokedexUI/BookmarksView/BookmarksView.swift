import SwiftUI
import SwiftData

struct BookmarksView: View {
    @Environment(\.pokemonData) private var allPokemon: [PokemonViewModel]
    @Query private var bookmarks: [BookmarkedPokemon]

    var body: some View {
        let favouriteVMs = allPokemon.filter { vm in
            bookmarks.contains(where: { $0.id == vm.id })
        }
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
                .navigationTitle("Favourites")
            }
        }
    }
}

#Preview {
    BookmarksView()
}
