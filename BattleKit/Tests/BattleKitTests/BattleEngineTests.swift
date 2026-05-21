import Testing
@testable import BattleKit

@Suite("Battle engine")
struct BattleEngineTests {
    static let chart = TypeChart(attackers: [
        "fire": TypeMatchup(doubleDamageTo: ["grass"], halfDamageTo: ["water", "fire"], noDamageTo: []),
        "water": TypeMatchup(doubleDamageTo: ["fire"], halfDamageTo: ["grass", "water"], noDamageTo: []),
        "normal": TypeMatchup(doubleDamageTo: [], halfDamageTo: [], noDamageTo: ["ghost"]),
        "electric": TypeMatchup(doubleDamageTo: ["water"], halfDamageTo: [], noDamageTo: []),
    ])

    static func pokemon(
        name: String = "Test",
        types: [String] = ["normal"],
        hp: Int = 100,
        attack: Int = 80,
        defense: Int = 80,
        spAttack: Int = 80,
        spDefense: Int = 80,
        speed: Int = 80
    ) -> TestPokemon {
        TestPokemon(
            id: 1, name: name, frontSprite: "", backSprite: nil,
            typeNames: types,
            statLookup: [
                "hp": hp, "attack": attack, "defense": defense,
                "special-attack": spAttack, "special-defense": spDefense, "speed": speed
            ]
        )
    }

    static func move(
        name: String = "tackle",
        power: Int? = 50,
        damageClass: String = "physical",
        typeName: String = "normal",
        accuracy: Int? = 100,
        priority: Int = 0,
        ailment: String = "none",
        ailmentChance: Int = 0,
        drain: Int = 0,
        healing: Int = 0,
        effectChance: Int? = nil,
        statChangeNames: [String] = [],
        statChangeDeltas: [Int] = [],
        isRechargeMove: Bool = false,
        hasSelfDebuff: Bool = false
    ) -> BattleMoveSnapshot {
        BattleMoveSnapshot(
            name: name, displayName: name.capitalized, power: power, accuracy: accuracy,
            priority: priority, damageClass: damageClass, typeName: typeName,
            ailment: ailment, ailmentChance: ailmentChance, drain: drain, healing: healing,
            effectChance: effectChance, statChangeNames: statChangeNames,
            statChangeDeltas: statChangeDeltas,
            isRechargeMove: isRechargeMove, hasSelfDebuff: hasSelfDebuff
        )
    }

    @Test func roundEmitsUsedEvents() {
        let p = BattleCombatant(pokemon: Self.pokemon(name: "Player", speed: 100), moves: [])
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Opponent", speed: 50), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let events = engine.resolveRound(playerMove: Self.move(), opponentMove: Self.move())
        let usedNames = events.compactMap { event -> String? in
            if case .used(_, let name) = event { return name }
            return nil
        }
        #expect(usedNames.count == 2)
    }

    @Test func fasterGoesFirst() {
        let p = BattleCombatant(pokemon: Self.pokemon(name: "Fast", speed: 200), moves: [])
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Slow", speed: 10), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let events = engine.resolveRound(playerMove: Self.move(), opponentMove: Self.move())
        if case .used(.player, _) = events.first {
            // Player went first as expected
        } else {
            Issue.record("Faster Pokemon should go first")
        }
    }

    @Test func priorityOverridesSpeed() {
        let p = BattleCombatant(pokemon: Self.pokemon(name: "Slow", speed: 10), moves: [])
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Fast", speed: 200), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let quickAttack = Self.move(name: "quick-attack", priority: 1)
        let events = engine.resolveRound(playerMove: quickAttack, opponentMove: Self.move())
        if case .used(.player, _) = events.first {
            // Priority move went first
        } else {
            Issue.record("Priority move should go first regardless of speed")
        }
    }

    @Test func damageReducesHP() {
        let p = BattleCombatant(pokemon: Self.pokemon(name: "Attacker", speed: 200), moves: [])
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Defender", speed: 10), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let startHP = engine.state.opponent.currentHP
        _ = engine.resolveRound(playerMove: Self.move(power: 80), opponentMove: Self.move(power: 0))
        #expect(engine.state.opponent.currentHP < startHP)
    }

    @Test func faintEndsMatch() {
        let p = BattleCombatant(pokemon: Self.pokemon(name: "Attacker", attack: 999, speed: 200), moves: [])
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Victim", hp: 1, speed: 10), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let events = engine.resolveRound(playerMove: Self.move(power: 200), opponentMove: Self.move())
        let ended = events.contains { if case .ended = $0 { return true }; return false }
        let fainted = events.contains { if case .fainted(.opponent) = $0 { return true }; return false }
        #expect(ended)
        #expect(fainted)
    }

    @Test func healingRestoresHP() {
        var p = BattleCombatant(pokemon: Self.pokemon(name: "Healer", speed: 200), moves: [])
        p.currentHP = p.maxHP / 2
        let halfHP = p.currentHP
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Opponent", speed: 10), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let healMove = Self.move(name: "synthesis", power: nil, damageClass: "status", healing: 50)
        _ = engine.resolveRound(playerMove: healMove, opponentMove: Self.move(power: 0))
        #expect(engine.state.player.currentHP > halfHP)
    }

    @Test func rechargeMoveSkipsNextTurn() {
        let p = BattleCombatant(pokemon: Self.pokemon(name: "Recharg", speed: 200), moves: [])
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Foe", speed: 10), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let hyperBeam = Self.move(name: "hyper-beam", power: 150, isRechargeMove: true)
        _ = engine.resolveRound(playerMove: hyperBeam, opponentMove: Self.move(power: 0))
        #expect(engine.state.player.mustRecharge == true)
        let events2 = engine.resolveRound(playerMove: Self.move(), opponentMove: Self.move(power: 0))
        let recharging = events2.contains { if case .recharging(.player) = $0 { return true }; return false }
        #expect(recharging)
    }

    @Test func statusTickDamage() {
        var p = BattleCombatant(pokemon: Self.pokemon(name: "Burned", speed: 200), moves: [])
        p.status = .burn
        let o = BattleCombatant(pokemon: Self.pokemon(name: "Foe", speed: 10), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        let startHP = engine.state.player.currentHP
        _ = engine.resolveRound(playerMove: Self.move(power: 0), opponentMove: Self.move(power: 0))
        #expect(engine.state.player.currentHP < startHP)
    }

    @Test func phaseResetsAfterRound() {
        let p = BattleCombatant(pokemon: Self.pokemon(speed: 100), moves: [])
        let o = BattleCombatant(pokemon: Self.pokemon(speed: 50), moves: [])
        var engine = BattleEngine(state: BattleState(player: p, opponent: o), typeChart: Self.chart)
        _ = engine.resolveRound(playerMove: Self.move(power: 10), opponentMove: Self.move(power: 10))
        if case .selectingMove = engine.state.phase {} else {
            Issue.record("Phase should reset to selectingMove after non-fatal round")
        }
    }
}
