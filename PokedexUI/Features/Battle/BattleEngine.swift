import Foundation

/// Pure battle logic. Synchronous turn resolver — caller (BattleViewModel)
/// drives event playback with delays for animation. Main-actor isolated to
/// match `TypeChartLoader` (which reads its dictionary on the main actor).
@MainActor
final class BattleEngine {
    private(set) var state: BattleState
    private let typeChart: TypeChartLoader

    init(state: BattleState, typeChart: TypeChartLoader) {
        self.state = state
        self.typeChart = typeChart
    }

    /// Resolve one round given the player's chosen move. AI picks a random move
    /// from its known moveset. Returns the ordered list of events to animate.
    func resolveRound(playerMove: MoveDetail) -> [BattleEvent] {
        guard case .selectingMove = state.phase else { return [] }
        var events: [BattleEvent] = []
        state.phase = .resolving

        guard let opponentMove = state.opponent.moves.randomElement() else {
            state.phase = .ended(winner: .player)
            events.append(.ended(winner: .player))
            return events
        }

        // Order: priority desc, then effective speed desc, ties broken by coin flip.
        let order: [BattleSide] = orderedSides(
            playerMove: playerMove,
            opponentMove: opponentMove
        )

        for side in order {
            if combatant(side).isFainted || combatant(side.opposite).isFainted { continue }
            let move = side == .player ? playerMove : opponentMove
            performAction(side: side, move: move, events: &events)
            if combatant(side.opposite).isFainted {
                events.append(.fainted(side.opposite))
                state.phase = .ended(winner: side)
                events.append(.ended(winner: side))
                return events
            }
        }

        // End-of-turn status ticks.
        for side in order {
            applyStatusTick(side: side, events: &events)
            if combatant(side).isFainted {
                events.append(.fainted(side))
                state.phase = .ended(winner: side.opposite)
                events.append(.ended(winner: side.opposite))
                return events
            }
        }

        state.phase = .selectingMove
        return events
    }

    // MARK: - Action

    private func performAction(side: BattleSide, move: MoveDetail, events: inout [BattleEvent]) {
        events.append(.used(side, moveName: move.displayName))

        // Paralysis full-skip check.
        if combatant(side).status == .paralysis, Double.random(in: 0..<1) < 0.25 {
            events.append(.fullyParalyzed(side))
            return
        }

        // Accuracy roll. Status moves with nil accuracy always hit (treat as 100%).
        let accuracy = Double(move.accuracy ?? 100) / 100.0
        guard Double.random(in: 0..<1) < accuracy else {
            events.append(.missed(side))
            return
        }

        // Damage calc.
        if let power = move.power, power > 0, move.damageClassKind != .status {
            let attacker = combatant(side)
            let defender = combatant(side.opposite)
            let (damage, effectiveness, crit) = computeDamage(
                power: power,
                move: move,
                attacker: attacker,
                defender: defender
            )
            mutate(side.opposite) { $0.currentHP = max(0, $0.currentHP - damage) }
            events.append(.damaged(side.opposite, amount: damage, effectiveness: effectiveness, crit: crit))
        }

        // Status application.
        let ailment = parseStatus(move.ailment)
        if ailment != .none, move.ailmentChance > 0 || move.damageClassKind == .status {
            let chance = move.ailmentChance > 0 ? Double(move.ailmentChance) / 100.0 : 1.0
            if combatant(side.opposite).status == .none, Double.random(in: 0..<1) < chance {
                mutate(side.opposite) { $0.status = ailment }
                events.append(.statusApplied(side.opposite, ailment))
            }
        }

        // Stat changes (Tail Whip, Growl, Swords Dance, etc.). Negative delta hits
        // the opponent; positive boosts the user. Good enough for the common cases.
        for (index, statName) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
            let delta = move.statChangeDeltas[index]
            guard delta != 0 else { continue }
            let target: BattleSide = delta < 0 ? side.opposite : side
            mutate(target) { $0.applyStage(statName, delta: delta) }
            events.append(.statChanged(target, stat: statName, delta: delta))
        }
    }

    private func computeDamage(
        power: Int,
        move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant
    ) -> (Int, Double, Bool) {
        let level = 50.0
        let isSpecial = move.damageClassKind == .special

        let atkStatName = isSpecial ? "special-attack" : "attack"
        let defStatName = isSpecial ? "special-defense" : "defense"
        let atkBase = isSpecial ? attacker.specialAttack : attacker.attack
        let defBase = isSpecial ? defender.specialDefense : defender.defense
        let atk = Double(atkBase) * statStageMultiplier(attacker.stage(for: atkStatName))
        let def = Double(defBase) * statStageMultiplier(defender.stage(for: defStatName))

        let stab = attacker.typeNames.contains(move.typeName) ? 1.5 : 1.0
        let typeMult = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
        let crit = Double.random(in: 0..<1) < (1.0 / 24.0)
        let critMult = crit ? 1.5 : 1.0
        let randVar = Double.random(in: 0.85...1.0)
        let burnPenalty = (attacker.status == .burn && !isSpecial) ? 0.5 : 1.0

        let base = ((2.0 * level / 5.0 + 2.0) * Double(power) * atk / def) / 50.0 + 2.0
        let total = base * stab * typeMult * critMult * randVar * burnPenalty
        let damage = typeMult == 0 ? 0 : max(1, Int(total))
        return (damage, typeMult, crit)
    }

    // MARK: - Status

    private func applyStatusTick(side: BattleSide, events: inout [BattleEvent]) {
        let c = combatant(side)
        guard !c.isFainted else { return }
        switch c.status {
        case .burn:
            let damage = max(1, c.maxHP / 16)
            mutate(side) { $0.currentHP = max(0, $0.currentHP - damage) }
            events.append(.statusTick(side, .burn, amount: damage))
        case .poison:
            let damage = max(1, c.maxHP / 8)
            mutate(side) { $0.currentHP = max(0, $0.currentHP - damage) }
            events.append(.statusTick(side, .poison, amount: damage))
        case .paralysis, .none:
            break
        }
    }

    private func parseStatus(_ raw: String) -> BattleStatus {
        switch raw {
        case "paralysis": return .paralysis
        case "burn": return .burn
        case "poison", "bad-poison": return .poison
        default: return .none
        }
    }

    // MARK: - Ordering

    private func orderedSides(playerMove: MoveDetail, opponentMove: MoveDetail) -> [BattleSide] {
        let playerKey = (playerMove.priority, state.player.effectiveSpeed)
        let opponentKey = (opponentMove.priority, state.opponent.effectiveSpeed)
        if playerKey.0 != opponentKey.0 {
            return playerKey.0 > opponentKey.0 ? [.player, .opponent] : [.opponent, .player]
        }
        if playerKey.1 != opponentKey.1 {
            return playerKey.1 > opponentKey.1 ? [.player, .opponent] : [.opponent, .player]
        }
        return Bool.random() ? [.player, .opponent] : [.opponent, .player]
    }

    // MARK: - State helpers

    private func combatant(_ side: BattleSide) -> BattleCombatant {
        side == .player ? state.player : state.opponent
    }

    private func mutate(_ side: BattleSide, _ body: (inout BattleCombatant) -> Void) {
        if side == .player {
            body(&state.player)
        } else {
            body(&state.opponent)
        }
    }
}
