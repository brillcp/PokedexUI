import Foundation

struct PokemonSpecies: Decodable, Sendable {
    let habitat: APINamed?
    let flavorTextEntries: [FlavorTextEntry]
    let varieties: [Variety]

    private enum CodingKeys: String, CodingKey {
        case habitat
        case flavorTextEntries = "flavor_text_entries"
        case varieties
    }

    var defaultVariety: Variety? {
        varieties.first(where: \.isDefault) ?? varieties.first
    }

    var englishFlavorText: String? {
        flavorTextEntries
            .first(where: { $0.language.name == "en" })?
            .flavorText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\u{000C}", with: " ")
    }
}

struct APINamed: Decodable, Sendable {
    let name: String
}

struct FlavorTextEntry: Decodable, Sendable {
    let flavorText: String
    let language: APINamed

    private enum CodingKeys: String, CodingKey {
        case flavorText = "flavor_text"
        case language
    }
}

struct Variety: Decodable, Sendable {
    let isDefault: Bool
    let pokemon: PokemonReference

    private enum CodingKeys: String, CodingKey {
        case isDefault = "is_default"
        case pokemon
    }

    struct PokemonReference: Decodable, Sendable {
        let name: String
        let url: String
    }
}
