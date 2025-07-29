import SwiftUI

// Environment key for pokemon data
struct PokemonDataKey: EnvironmentKey {
    static let defaultValue: [PokemonViewModel] = []
}

// MARK: -
extension EnvironmentValues {
    var pokemonData: [PokemonViewModel] {
        get { self[PokemonDataKey.self] }
        set { self[PokemonDataKey.self] = newValue }
    }
}
