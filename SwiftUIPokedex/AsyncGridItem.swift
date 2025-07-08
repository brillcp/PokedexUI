//
//  AsyncGridItem.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import SwiftUI

struct AsyncImageView: View {
    private let shared: ImageLoader = .shared

    @State private var image: UIImage?
    @State private var color: Color?

    let urlString: String
    var onColorExtracted: ((Color) -> Void?)? = nil

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .task {
                        image = await shared.loadImage(from: urlString)
                        if let uiColor = image?.dominantColor {
                            let swiftUIColor = Color(uiColor: uiColor)
                            color = swiftUIColor
                            onColorExtracted?(swiftUIColor)
                        }
                    }
            }
        }
        .frame(width: 150, height: 150)
        .background(color)
        .cornerRadius(20)
    }
}

/*
struct AsyncGridItem: View {
    
    // MARK: Private properties
    @State private var loader: ImageLoader
    
    // MARK: - Public properties
    var pokemon: PokemonDetails
    
    var image: UIImage? {
        loader.image
    }
    
    var color: Color {
        Color(uiColor: image?.dominantColor ?? .darkGray)
    }
    
    // MARK: - Init
    init(pokemon: PokemonDetails, url: String) {
        self.pokemon = pokemon
        _loader = StateObject(wrappedValue: ImageLoader(url: URL(string: url)!))
    }
    
    // MARK: - Content
    var body: some View {
        VStack {
            if let img = loader.image, let color = img.dominantColor {
                VStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                    
                    Text(pokemon.name)
                        .foregroundColor(color.isLight ? .black : .white)
                    Spacer()
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 150, height: 150)
        .background(Color(uiColor: loader.image?.dominantColor ?? .darkGray))
        .cornerRadius(20)
        .overlay(NumberOverlay(number: pokemon.id, isLight: loader.image?.dominantColor?.isLight ?? false), alignment: .topTrailing)
        .onAppear(perform: loader.load)
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


struct AsyncGridItem_Previews: PreviewProvider {
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
        
        AsyncGridItem(pokemon: pokemon, url: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/6.png")
    }
}

 */

#Preview {
    AsyncImageView(urlString: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/6.png") { _ in }
}
