//
//  DetailView.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import SwiftUI

struct DetailView<ViewModel: PokemonViewModelProtocol>: View {
    var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    HStack {
//                        ForEach(pokemon.types, id: \.type) {
//                            Text($0.type.name)
//                        }
                        Spacer()
                        Text("#\(viewModel.id)")
                    }
                    
                    AsyncGridItem(viewModel: viewModel)
                    DetailStack()
                }
                .padding()
                .background(viewModel.color)

            }
            .background(Color.darkGrey)
            .foregroundColor(viewModel.isLight ? .black : .white)
            .navigationTitle(viewModel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(viewModel.color ?? .darkGrey, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
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
    }
}

#Preview {
    DetailView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
