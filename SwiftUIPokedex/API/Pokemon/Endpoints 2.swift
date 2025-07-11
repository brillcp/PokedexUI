//
//  Endpoints.swift
//  SwiftPokedex
//
//  Created by Viktor Gidlöf on 2022-11-30.
//

import Networking

/// An enumeration for all the possible endpoints for the backend
enum Endpoint {
    case itemDetails(String)
    case details(String)
    case pokemon
    case items
}

// MARK: -
extension Endpoint: EndpointType {

    var path: String {
        switch self {
        case .itemDetails(let id): return "item/\(id)"
        case .details(let id): return "pokemon/\(id)"
        case .pokemon: return "pokemon"
        case .items: return "item"
        }
    }
}
