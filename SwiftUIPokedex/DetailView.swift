//
//  DetailView.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import SwiftUI

struct DetailView: View {
    @State private var dominantColor: Color = .darkGrey

    var pokemon: PokemonViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    HStack {
//                        ForEach(pokemon.types, id: \.type) {
//                            Text($0.type.name)
//                        }
                        Spacer()
                        Text("#\(1)")
                    }
                    
                    AsyncGridItem(urlString: "pokemon.sprite.url") {
                        dominantColor = $0
                    }
                    DetailStack()
                }
                .padding()
                .background(dominantColor)
                
            }
            .background(Color.darkGrey)
            .foregroundColor(dominantColor.isLight ? .black : .white)
            .navigationTitle("pokemon.name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dominantColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    let pokemon = PokemonDetails(
        id: 0,
        name: "Pika",
        weight: 0,
        height: 0,
        baseExperience: 0,
        forms: [],
        sprite: Sprite(url: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/6.png"),
        abilities: [],
        moves: [],
        types: [.init(type: .init(name: "gunther", url: ""))],
        stats: []
    )
    let vm = PokemonViewModel(pokemon: pokemon)
    DetailView(pokemon: vm)
}

struct DetailStack: View {
    var body: some View {
        HStack {
            VStack {
                Text("Height")
                Text("xxx")
            }
            
            Spacer()
            
            VStack {
                Text("Width")
                Text("xxx")
            }
        }
        .padding([.leading, .trailing, .bottom], 30)
    }
}
