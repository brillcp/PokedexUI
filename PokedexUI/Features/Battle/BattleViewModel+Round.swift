import SwiftUI

extension BattleViewModel {
    func submit(_ move: MoveDetail) async {
        guard let engine,
              let typeChart,
              !isResolvingTurn,
              winner == nil,
              let snapshot = state
        else { return }
        animator.attackTick += 1
        isResolvingTurn = true

        let opponentMove = await brain.nextMove(
            attacker:  snapshot.opponent,
            defender:  snapshot.player,
            moves:     snapshot.opponent.moves,
            typeChart: typeChart
        )
        let events = engine.resolveRound(playerMove: move, opponentMove: opponentMove)
        for event in events {
            let line = formatter.format(
                event,
                playerColor:   animator.playerCues.color,
                opponentColor: animator.opponentCues.color
            )
            log.append(line)
            #if DEBUG
            print("⚔️ \(line)")
            #endif
            apply(event)
            await play(event)
            try? await Task.sleep(for: .milliseconds(650))
            if case .ended(let w) = event {
                winner = w ?? .player
                await playWinnerCry()
                break
            }
        }
        state = engine.state
        isResolvingTurn = false
    }
}

private extension BattleViewModel {
    func apply(_ event: BattleEvent) {
        guard var snapshot = state else { return }
        switch event {
        case .damaged(let side, let amount, _, _),
             .statusTick(let side, _, let amount),
             .recoil(let side, let amount):
            mutate(side, in: &snapshot) { $0.currentHP = max(0, $0.currentHP - amount) }
            animator.postDamage(side: side, amount: amount)
        case .healed(let side, let amount):
            mutate(side, in: &snapshot) { $0.currentHP = min($0.maxHP, $0.currentHP + amount) }
        case .statusApplied(let side, let status):
            mutate(side, in: &snapshot) {
                $0.status = status
                if status == .sleep { $0.sleepTurns = 2 }
            }
        case .wokeUp(let side):
            mutate(side, in: &snapshot) { $0.status = .none; $0.sleepTurns = 0 }
        case .statChanged(let side, let stat, let delta):
            mutate(side, in: &snapshot) { $0.applyStage(stat, delta: delta) }
        case .used, .missed, .fullyParalyzed, .fastAsleep, .recharging, .fainted, .ended:
            break
        }
        state = snapshot
    }

    func mutate(_ side: BattleSide, in state: inout BattleState, _ body: (inout BattleCombatant) -> Void) {
        if side == .player {
            body(&state.player)
        } else {
            body(&state.opponent)
        }
    }

    func play(_ event: BattleEvent) async {
        switch event {
        case .used(let side, _):
            await animator.playAttack(side: side)
        case .damaged(let side, let amount, let effectiveness, _):
            await animator.playHit(side: side, amount: amount, effectiveness: effectiveness)
        case .recoil(let side, let amount):
            await animator.playRecoil(side: side, amount: amount)
        case .fainted(let side):
            await animator.playFaint(side: side)
        default:
            break
        }
    }
}
