//
//  DetailView.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import SwiftUI

struct DetailView: View {
    
    var pokemon: PokemonDetails
    
    var item: AsyncGridItem {
        AsyncGridItem(pokemon: pokemon, url: "")
    }
    
    var body: some View {
        ScrollView {
            VStack {
                
                HStack {
                    ForEach(pokemon.types, id: \.type) { aa in
                        Text("aa")
                    }
                    Spacer()
                    Text("#\(pokemon.id)")
                        .foregroundColor(.white)
                }
                
                
                AsyncImage(
                    url: URL(string: pokemon.sprite.url),
                    content: { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                    },
                    placeholder: {
                        ProgressView()
                    }
                )
                
                DetailStack()
            }
            .background(.green)

        }
        .background(Color.darkGrey)
        .navigationTitle(pokemon.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        
        let pokemon = PokemonDetails(id: 0,
                                     name: "Pika",
                                     weight: 0,
                                     height: 0,
                                     baseExperience: 0,
                                     forms: [],
                                     sprite: Sprite(url: ""),
                                     abilities: [],
                                     moves: [],
                                     types: [],
                                     stats: [])
        
        DetailView(pokemon: pokemon)
    }
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
        .foregroundColor(.white)
    }
}
