import Foundation

/// Pure battle logic. Synchronous turn resolver: the caller
/// (`BattleViewModel`) drives event playback with delays for animation. Stays
/// on `MainActor` so `withAnimation` callbacks fired from `BattleViewModel`
/// see consistent state, but the engine itself doesn't touch UIKit; the
/// `TypeChart` value it holds is a Sendable snapshot, so lookups are free of
/// actor hops.
@MainActor
final class BattleEngine {
    private(set) var state: BattleState
    private let typeChart: TypeChart

    init(state: BattleState, typeChart: TypeChart) {
        self.state = state
        self.typeChart = typeChart
    }

    /// Resolve one round given both sides' chosen moves. The opponent's move
    /// is picked by the caller (`BattleViewModel`), typically via
    /// `BattleAIService`, falling back to random. Returns the ordered list of
    /// events to animate.
    func resolveRound(playerMove: MoveDetail, opponentMove: MoveDetail) -> [BattleEvent] {
        guard case .selectingMove = state.phase else { return [] }
        var events: [BattleEvent] = []
        state.phase = .resolving

        // Order: priority desc, then effective speed desc, ties broken by coin flip.
        let order: [BattleSide] = orderedSides(
            playerMove: playerMove,
            opponentMove: opponentMove
        )

        for side in order {
            if combatant(side).isFainted || combatant(side.opposite).isFainted { continue }
            let move = side == .player ? playerMove : opponentMove
            performAction(side: side, move: move, events: &events)

            // Recoil self-faint.
            if combatant(side).isFainted {
                events.append(.fainted(side))
                state.phase = .ended(winner: side.opposite)
                events.append(.ended(winner: side.opposite))
                return events
            }

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

}

// MARK: - Private

private extension BattleEngine {
    func performAction(side: BattleSide, move: MoveDetail, events: inout [BattleEvent]) {
        events.append(.used(side, moveName: move.displayName))
        let baselineEventCount = events.count

        // Recharge check: skip turn, clear flag.
        if combatant(side).mustRecharge {
            mutate(side) { $0.mustRecharge = false }
            events.append(.recharging(side))
            return
        }

        // Sleep check: decrement counter, skip turn if still asleep.
        if combatant(side).status == .sleep {
            mutate(side) { $0.sleepTurns -= 1 }
            if combatant(side).sleepTurns > 0 {
                events.append(.fastAsleep(side))
                return
            }
            mutate(side) { $0.status = .none }
            events.append(.wokeUp(side))
        }

        // Paralysis full-skip check.
        if combatant(side).status == .paralysis, Double.random(in: 0..<1) < 0.25 {
            events.append(.fullyParalyzed(side))
            return
        }

        // Rest: full heal + self-sleep 2 turns.
        if move.name == "rest" {
            let c = combatant(side)
            let healed = c.maxHP - c.currentHP
            if healed > 0 {
                mutate(side) { $0.currentHP = $0.maxHP }
                events.append(.healed(side, amount: healed))
            }
            mutate(side) { $0.status = .sleep; $0.sleepTurns = 2 }
            events.append(.statusApplied(side, .sleep))
            return
        }

        // Pure healing moves (Recover, Roost, Moonlight, etc.).
        if move.healing > 0 {
            let c = combatant(side)
            let amount = min(c.maxHP * move.healing / 100, c.maxHP - c.currentHP)
            if amount > 0 {
                mutate(side) { $0.currentHP += amount }
                events.append(.healed(side, amount: amount))
            }
            return
        }

        // Accuracy roll. Status moves with nil accuracy always hit (treat as 100%).
        let accuracy = Double(move.accuracy ?? 100) / 100.0
        guard Double.random(in: 0..<1) < accuracy else {
            events.append(.missed(side))
            return
        }

        // Damage calc.
        var damageDealt = 0
        if let power = move.power, power > 0, move.damageClassKind != .status {
            let attacker = combatant(side)
            let defender = combatant(side.opposite)
            let (damage, effectiveness, crit) = computeDamage(
                power: power,
                move: move,
                attacker: attacker,
                defender: defender
            )
            damageDealt = damage
            mutate(side.opposite) { $0.currentHP = max(0, $0.currentHP - damage) }
            events.append(.damaged(side.opposite, amount: damage, effectiveness: effectiveness, crit: crit))
        }

        // Recharge flag: user must skip next turn.
        if move.isRechargeMove { mutate(side) { $0.mustRecharge = true } }

        // Drain (positive = heal attacker by % of damage, e.g. Giga Drain).
        if move.drain > 0, damageDealt > 0 {
            let healed = max(1, damageDealt * move.drain / 100)
            mutate(side) { $0.currentHP = min($0.maxHP, $0.currentHP + healed) }
            events.append(.healed(side, amount: healed))
        }

        // Recoil (negative drain = attacker takes damage, e.g. Brave Bird).
        if move.drain < 0, damageDealt > 0 {
            let recoilDmg = max(1, damageDealt * abs(move.drain) / 100)
            mutate(side) { $0.currentHP = max(0, $0.currentHP - recoilDmg) }
            events.append(.recoil(side, amount: recoilDmg))
        }

        // Status application.
        let ailment = parseStatus(move.ailment)
        if ailment != .none, move.ailmentChance > 0 || move.damageClassKind == .status {
            let chance = move.ailmentChance > 0 ? Double(move.ailmentChance) / 100.0 : 1.0
            let target: BattleSide = ailment == .sleep ? side.opposite : side.opposite
            if combatant(target).status == .none, Double.random(in: 0..<1) < chance {
                mutate(target) {
                    $0.status = ailment
                    if ailment == .sleep { $0.sleepTurns = Int.random(in: 1...3) }
                }
                events.append(.statusApplied(target, ailment))
            }
        }

        // Stat changes. Self-debuff moves (Leaf Storm, Close Combat, etc.)
        // always hit the user; status debuffs (Growl, Leer) hit the opponent;
        // self-buffs (Swords Dance) hit the user.
        for (index, statName) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
            let delta = move.statChangeDeltas[index]
            guard delta != 0 else { continue }
            let target: BattleSide
            if move.hasSelfDebuff {
                target = side
            } else {
                target = delta < 0 ? side.opposite : side
            }
            mutate(target) { $0.applyStage(statName, delta: delta) }
            events.append(.statChanged(target, stat: statName, delta: delta))
        }
        if events.count == baselineEventCount {
            events.append(.damaged(side.opposite, amount: 0, effectiveness: 0, crit: false))
        }
    }

    func computeDamage(
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

    func applyStatusTick(side: BattleSide, events: inout [BattleEvent]) {
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
        case .paralysis, .sleep, .none:
            break
        }
    }

    func parseStatus(_ raw: String) -> BattleStatus {
        switch raw {
        case "paralysis": return .paralysis
        case "burn": return .burn
        case "poison", "bad-poison": return .poison
        case "sleep": return .sleep
        default: return .none
        }
    }

    // MARK: - Ordering

    func orderedSides(playerMove: MoveDetail, opponentMove: MoveDetail) -> [BattleSide] {
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

    func combatant(_ side: BattleSide) -> BattleCombatant {
        side == .player ? state.player : state.opponent
    }

    func mutate(_ side: BattleSide, _ body: (inout BattleCombatant) -> Void) {
        if side == .player {
            body(&state.player)
        } else {
            body(&state.opponent)
        }
    }
}
