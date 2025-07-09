//
//  AsyncGridItem.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import SwiftUI

struct AsyncGridItem<ViewModel: PokemonViewModelProtocol>: View {
    private let shared: ImageLoader = .shared

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Group {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .task { await viewModel.loadSprite() }
            }
        }
        .frame(width: 150, height: 150)
        .background(viewModel.color)
        .cornerRadius(20)
    }
}

#Preview {
    AsyncGridItem(viewModel: PokemonViewModel(pokemon: .pikachu))
}
