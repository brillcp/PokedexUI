import Foundation

/// Canonical move-name sets for classification.
public enum MoveClassification {
    public static let selfDebuffMoves: Set<String> = [
        "leaf-storm", "overheat", "draco-meteor", "fleur-cannon", "psycho-boost",
        "close-combat", "superpower", "v-create", "hammer-arm", "ice-hammer",
        "headlong-rush", "clanging-scales", "shell-smash"
    ]

    public static let rechargeMoves: Set<String> = [
        "blast-burn", "frenzy-plant", "giga-impact", "hydro-cannon",
        "hyper-beam", "meteor-assault", "prismatic-laser",
        "roar-of-time", "rock-wrecker"
    ]

    public static let chargingMoves: Set<String> = [
        "sky-attack", "solar-beam", "solar-blade", "skull-bash",
        "razor-wind", "fly", "dig", "dive", "bounce", "phantom-force",
        "shadow-force", "geomancy", "meteor-beam"
    ]

    public static let selfKOMoves: Set<String> = [
        "explosion", "self-destruct", "memento", "healing-wish",
        "lunar-dance", "final-gambit", "misty-explosion"
    ]
}
