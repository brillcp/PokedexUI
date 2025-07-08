//
//  PokedexUI.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import SwiftUI

struct PokedexUI: View {
    @Namespace private var namespace

    private var gridLayout: [GridItem] = [
        GridItem(.flexible(minimum: 100, maximum: .infinity)),
        GridItem(.flexible(minimum: 100, maximum: .infinity))
    ]
    
    @ObservedObject private var api = PokemonAPI()
    @State private var dominantColor: Color = .darkGrey

    var body: some View {
        NavigationView {
            TabView {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridLayout, spacing: 20) {
                        ForEach(api.pokemon, id: \.id) { pokemon in
                            NavigationLink {
                                DetailView(pokemon: pokemon)
                                    .navigationTransition(.zoom(sourceID: pokemon.id, in: namespace))
                            } label: {
                                AsyncImageView(urlString: pokemon.sprite.url) { color in
                                    dominantColor = color
                                }
                                .overlay(alignment: .topTrailing) {
                                    NumberOverlay(
                                        number: pokemon.id,
                                        isLight: dominantColor.isLight
                                    )
                                }
                                .onAppear {
                                    if pokemon == api.pokemon.last {
                                        api.requestPokemon()
                                    }
                                }
                            }
                            .tag(pokemon.id)
                        }
                    }
                    .padding(20)

                    if api.isLoading {
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
        .onAppear(perform: api.requestPokemon)
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
    PokedexUI()
}
