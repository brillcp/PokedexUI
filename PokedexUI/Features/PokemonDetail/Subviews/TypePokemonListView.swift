import SwiftUI
import SwiftData

/// Grid of all Pokemon matching a given type, pushed from a tappable
/// type chip in the detail view. Uses the same `PokemonSpriteCard` cells
/// as search and bookmarks.
struct TypePokemonListView: View {
    let typeName: String

    @Environment(\.container) private var container
    @Namespace private var namespace
    @Query(sort: \Pokemon.id) private var allPokemon: [Pokemon]
    @State private var selectedPokemon: Pokemon?

    var body: some View {
        PokemonGrid(pokemon: filtered) { pokemon in
            Button {
                selectedPokemon = pokemon
            } label: {
                PokemonSpriteCard(pokemon: pokemon)
                    .applyTransitionSource(id: pokemon.id, namespace: namespace)
            }
            .buttonStyle(.plain)
        }
        .applyPokedexStyling(title: typeName.capitalized, navColor: .darkGrey)
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

// MARK: - Private
private extension TypePokemonListView {
    var filtered: [Pokemon] {
        allPokemon.filter { pokemon in
            pokemon.types.contains { $0.type.name == typeName }
        }
    }
}
