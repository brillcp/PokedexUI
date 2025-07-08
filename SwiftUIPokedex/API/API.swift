//
//  API.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import Foundation
import Combine

class API {
    let baseURL = URL(string: "https://pokeapi.co/api/v2/")!
    var cancellables = Set<AnyCancellable>()
    
    enum ItemType: String {
        case pokemon
        case items = "item"
    }
}
