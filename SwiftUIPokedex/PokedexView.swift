//
//  PokedexUI.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    // MARK: - Properties
    @Namespace private var namespace
    @ObservedObject var viewModel: ViewModel

    private var gridLayout: [GridItem] = [
        GridItem(.flexible(minimum: 100, maximum: .infinity)),
        GridItem(.flexible(minimum: 100, maximum: .infinity))
    ]

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
            TabView {
                pokemonGridView
                placeholderTabView
            }
            .navigationTitle("Pokedex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokedexRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await viewModel.requestPokemon()
        }
    }
}

// MARK: - View Components
private extension PokedexView {
    var pokemonGridView: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: gridLayout, spacing: 20) {
                ForEach(viewModel.pokemon, id: \.id) {
                    pokemonGridItem(for: $0)
                }
            }
            .padding(20)

            if viewModel.isLoading {
                loadingView
            }
        }
        .background(Color.darkGrey)
    }

    func pokemonGridItem(for pokemon: PokemonViewModel) -> some View {
        NavigationLink {
            DetailView(viewModel: pokemon)
                .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
        } label: {
            gridItem(pokemon: pokemon)
        }
        .tag(pokemon.id)
    }

    func gridItem(pokemon: PokemonViewModel) -> some View {
        AsyncGridItem(viewModel: pokemon)
            .overlay(alignment: .topTrailing) {
                NumberOverlay(
                    number: pokemon.id,
                    isLight: pokemon.isLight
                )
            }
            .task {
                if pokemon == viewModel.pokemon.last {
                    await viewModel.requestPokemon()
                }
            }
    }

    var loadingView: some View {
        ProgressView()
            .tint(.white)
    }

    var placeholderTabView: some View {
        Text("dladl")
    }
}

// MARK: - Supporting Views
struct NumberOverlay: View {
    let number: Int
    let isLight: Bool

    var body: some View {
        Text("#\(number)")
            .foregroundColor(isLight ? .black : .white)
            .padding(10)
    }
}

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
