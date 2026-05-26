import SwiftUI
import SwiftData

/// Bookmarks tab showing Pokemon rows filtered by `isBookmarked`.
struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.container) private var container
    @Namespace private var namespace

    @Query(
        filter: #Predicate<Pokemon> { $0.isBookmarked },
        sort: \.id
    ) private var bookmarks: [Pokemon]

    @State private var selectedPokemon: Pokemon?

    var body: some View {
        NavigationStack {
            PokemonPickerGrid(
                pokemon: bookmarks,
                namespace: namespace
            ) { pokemon in
                selectedPokemon = pokemon
            }
                .background {
                    if bookmarks.isEmpty {
                        Text("No favourites")
                            .foregroundStyle(.secondary)
                            .font(.pixel14)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel, action: dismiss.callAsFunction)
                    }
                }
                .applyPokedexStyling(title: Tabs.favourites.title, navColor: .darkGrey)
                .navigationDestination(item: $selectedPokemon) { pokemon in
                    PokemonDetailView(
                        viewModel: PokemonDetailViewModel(
                            summary: pokemon,
                            container: container
                        )
                    )
                    .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
                }
        }
    }
}

#Preview {
    BookmarksView()
}
