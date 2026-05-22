import Foundation

/// Synchronous turn resolver for battle logic.
///
/// Pure value type with no UI or actor dependencies. Mutate via
/// `resolveRound` and read the updated `state` afterwards.
public struct BattleEngine: Sendable {
    private let typeChart: TypeChart

    public private(set) var state: BattleState

    public init(state: BattleState, typeChart: TypeChart) {
        self.state = state
        self.typeChart = typeChart
    }

    public mutating func resolveRound(
        playerMove: some BattleMoveData,
        opponentMove: some BattleMoveData
    ) -> [BattleEvent] {
        guard case .selectingMove = state.phase else { return [] }
        var events: [BattleEvent] = []
        state.phase = .resolving

        let order = orderedSides(playerMove: playerMove, opponentMove: opponentMove)
        var hitThisRound: Set<BattleSide> = []

        for side in order {
            if combatant(side).isFainted || combatant(side.opposite).isFainted { continue }
            switch side {
            case .player:
                performAction(side: .player, move: playerMove, events: &events, hitThisRound: &hitThisRound)
            case .opponent:
                performAction(side: .opponent, move: opponentMove, events: &events, hitThisRound: &hitThisRound)
            }

            if let result = checkFaint(after: side, events: &events) {
                return result
            }
        }

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
    mutating func performAction(
        side: BattleSide,
        move: some BattleMoveData,
        events: inout [BattleEvent],
        hitThisRound: inout Set<BattleSide>
    ) {
        events.append(.used(side, moveName: move.displayName))
        let baselineEventCount = events.count

        if combatant(side).mustRecharge {
            mutate(side) { $0.mustRecharge = false }
            events.append(.recharging(side))
            return
        }

        if move.name == "focus-punch", hitThisRound.contains(side) {
            events.append(.lostFocus(side))
            return
        }

        if combatant(side).status == .sleep {
            mutate(side) { $0.sleepTurns -= 1 }
            if combatant(side).sleepTurns > 0 {
                events.append(.fastAsleep(side))
                return
            }
            mutate(side) { $0.status = .none }
            events.append(.wokeUp(side))
        }

        if combatant(side).status == .paralysis, Double.random(in: 0..<1) < 0.25 {
            events.append(.fullyParalyzed(side))
            return
        }

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

        if move.healing > 0 {
            let c = combatant(side)
            let amount = min(c.maxHP * move.healing / 100, c.maxHP - c.currentHP)
            if amount > 0 {
                mutate(side) { $0.currentHP += amount }
                events.append(.healed(side, amount: amount))
            }
            return
        }

        let accuracy = Double(move.accuracy ?? 100) / 100.0
        guard Double.random(in: 0..<1) < accuracy else {
            events.append(.missed(side))
            return
        }

        if MoveClassification.requiresPoisonedTarget.contains(move.name),
           combatant(side.opposite).status != .poison {
            events.append(.damaged(side.opposite, amount: 0, effectiveness: 0, crit: false))
            return
        }

        var damageDealt = 0
        if let power = move.power, power > 0, move.damageClassKind != .status {
            let (damage, effectiveness, crit) = DamageCalculator.computeDamage(
                power: power,
                move: move,
                attacker: combatant(side),
                defender: combatant(side.opposite),
                typeChart: typeChart
            )
            damageDealt = damage
            mutate(side.opposite) { $0.currentHP = max(0, $0.currentHP - damage) }
            events.append(.damaged(side.opposite, amount: damage, effectiveness: effectiveness, crit: crit))
            if damage > 0 { hitThisRound.insert(side.opposite) }
        }

        if move.isRechargeMove { mutate(side) { $0.mustRecharge = true } }

        if move.drain > 0, damageDealt > 0 {
            let healed = max(1, damageDealt * move.drain / 100)
            mutate(side) { $0.currentHP = min($0.maxHP, $0.currentHP + healed) }
            events.append(.healed(side, amount: healed))
        }

        if move.drain < 0, damageDealt > 0 {
            let recoilDmg = max(1, damageDealt * abs(move.drain) / 100)
            mutate(side) { $0.currentHP = max(0, $0.currentHP - recoilDmg) }
            events.append(.recoil(side, amount: recoilDmg))
        }

        let ailment = BattleStatus(ailment: move.ailment)
        if ailment != .none, move.ailmentChance > 0 || move.damageClassKind == .status {
            let chance = move.ailmentChance > 0 ? Double(move.ailmentChance) / 100.0 : 1.0
            let target: BattleSide = side.opposite
            if combatant(target).status == .none, Double.random(in: 0..<1) < chance {
                mutate(target) {
                    $0.status = ailment
                    if ailment == .sleep { $0.sleepTurns = Int.random(in: 1...3) }
                }
                events.append(.statusApplied(target, ailment))
            }
        }

        let secondaryGate: Double = {
            guard move.damageClassKind != .status, let chance = move.effectChance else { return 1.0 }
            return Double(chance) / 100.0
        }()
        let triggersStatChange = move.hasSelfDebuff || Double.random(in: 0..<1) < secondaryGate
        if triggersStatChange {
            let allSelfTarget = move.hasSelfDebuff
                || (move.statChangeDeltas.contains { $0 > 0 } && move.statChangeDeltas.contains { $0 < 0 })
            for (index, statName) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
                let delta = move.statChangeDeltas[index]
                guard delta != 0 else { continue }
                let target: BattleSide = allSelfTarget ? side : (delta < 0 ? side.opposite : side)
                mutate(target) { $0.applyStage(statName, delta: delta) }
                events.append(.statChanged(target, stat: statName, delta: delta))
            }
        }

        if events.count == baselineEventCount {
            events.append(.damaged(side.opposite, amount: 0, effectiveness: 0, crit: false))
        }
    }

    mutating func applyStatusTick(side: BattleSide, events: inout [BattleEvent]) {
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

    func orderedSides(playerMove: some BattleMoveData, opponentMove: some BattleMoveData) -> [BattleSide] {
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

    func combatant(_ side: BattleSide) -> BattleCombatant {
        side == .player ? state.player : state.opponent
    }

    mutating func checkFaint(after side: BattleSide, events: inout [BattleEvent]) -> [BattleEvent]? {
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
        return nil
    }

    mutating func mutate(_ side: BattleSide, _ body: (inout BattleCombatant) -> Void) {
        if side == .player {
            body(&state.player)
        } else {
            body(&state.opponent)
        }
    }
}
