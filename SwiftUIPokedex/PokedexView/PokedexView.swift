//
//  PokedexUI.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import SwiftUI

struct PokedexView<ViewModel: PokedexViewModelProtocol>: View {
    @State private var dominantColor: Color = .darkGrey
    @Namespace private var namespace

    private var gridLayout: [GridItem] = [
        GridItem(.flexible(minimum: 100, maximum: .infinity)),
        GridItem(.flexible(minimum: 100, maximum: .infinity))
    ]

    @ObservedObject var viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationView {
            TabView {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridLayout, spacing: 20) {
                        ForEach(viewModel.pokemon, id: \.id) { pokemon in
                            NavigationLink {
                                DetailView(pokemon: pokemon)
                                    .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
                            } label: {
                                AsyncGridItem(urlString: pokemon.url) { color in
                                    dominantColor = color
                                }
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
                            .tag(pokemon.id)
                        }
                    }
                    .padding(20)

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .background(Color.darkGrey)

                Text("dladl")
            }
            .navigationTitle("Pokedex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokedexRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await viewModel.requestPokemon() }
    }
}

struct NumberOverlay: View {
    var number: Int
    var isLight: Bool

    var body: some View {
        Text("#\(number)")
            .foregroundColor(isLight ? .black : .white)
            .padding(10)
    }
}

#Preview {
    PokedexView(viewModel: PokedexViewModel())
}
