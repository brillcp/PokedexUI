import FoundationModels

// MARK: - Generable Results

@Generable(description: "The chosen move for this turn")
struct MovePickResult {
    @Guide(description: "Exact move name from the available list, e.g. 'thunderbolt'")
    var moveName: String
}

@Generable(description: "Four moves for the battle loadout")
struct LoadoutPickResult {
    @Guide(description: "Exactly 4 move names from the available list")
    var moveNames: [String]
}

@Generable(description: "The chosen opponent for this battle")
struct OpponentPickResult {
    @Guide(description: "The number of the chosen opponent from the list")
    var index: Int
}
