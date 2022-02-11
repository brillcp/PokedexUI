//
//  PokedexUI.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import SwiftUI

struct PokedexUI: View {
    
    private var gridLayout: [GridItem] = [
        GridItem(.flexible(minimum: 100, maximum: .infinity)),
        GridItem(.flexible(minimum: 100, maximum: .infinity))
    ]
    
    @ObservedObject private var api = PokemonAPI()
    
    var body: some View {
        NavigationView {
            TabView {
                ScrollView {
                    LazyVGrid(columns: gridLayout, spacing: 20) {
                        ForEach(api.pokemon, id: \.name) { pokemon in
                            NavigationLink(destination: DetailView(pokemon: pokemon)) {
                                AsyncGridItem(pokemon: pokemon, url: pokemon.sprite.url)
                                    .onAppear {
                                        if pokemon == api.pokemon.last {
                                            api.requestPokemon()
                                        }
                                    }
                            }
                        }
                    }
                    .padding(20)
                    
                    if api.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .background(Color.darkGrey)
            }
            .navigationTitle("Pokedex")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: api.requestPokemon)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PokedexUI()
    }
}
