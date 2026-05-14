import Foundation

struct PokemonSpecies: Decodable, Sendable {
    let habitat: APINamed?
    let flavorTextEntries: [FlavorTextEntry]
    let varieties: [Variety]
    let genera: [Genus]
    let genderRate: Int
    let captureRate: Int
    let baseHappiness: Int?
    let generation: APINamed?
    let evolutionChain: EvolutionChainRef?
    let isLegendary: Bool
    let isMythical: Bool

    private enum CodingKeys: String, CodingKey {
        case habitat
        case flavorTextEntries = "flavor_text_entries"
        case varieties
        case genera
        case genderRate = "gender_rate"
        case captureRate = "capture_rate"
        case baseHappiness = "base_happiness"
        case generation
        case evolutionChain = "evolution_chain"
        case isLegendary = "is_legendary"
        case isMythical = "is_mythical"
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

    var englishGenus: String? {
        genera.first(where: { $0.language.name == "en" })?.genus
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

struct Genus: Decodable, Sendable {
    let genus: String
    let language: APINamed
}

struct EvolutionChainRef: Decodable, Sendable {
    let url: String

    /// Last path component is the chain id.
    var id: String? {
        URL(string: url)?
            .pathComponents
            .last(where: { !$0.isEmpty && $0 != "/" })
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
