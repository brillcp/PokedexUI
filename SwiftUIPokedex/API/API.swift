//
//  API.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import Foundation

class API {
    let baseURL = URL(string: "https://pokeapi.co/api/v2/")!
    
    enum ItemType: String {
        case pokemon
        case items = "item"
    }
}
