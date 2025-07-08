//
//  SwiftUIPokedexApp.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import SwiftUI

@main
struct SwiftUIPokedexApp: App {
    var body: some Scene {
        WindowGroup {
            PokedexView(viewModel: PokedexViewModel())
        }
    }
}
