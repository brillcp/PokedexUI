import SwiftUI
import PokeBattleKit

/// Per-side animation cue bundle.
struct BattleSideCues: Equatable {
    var shakeTick: Int = 0
    var damageAmount: Int?
    var damageTick: Int = 0
    var color: Color?
}

/// Owns all animation cues the battle UI reads.
@MainActor
@Observable
final class BattleAnimator {
    var attackingSide: BattleSide?
    var faintedSide: BattleSide?
    var hasEntered: Bool = false
    var playerCues:   BattleSideCues = BattleSideCues()
    var opponentCues: BattleSideCues = BattleSideCues()
    var attackTick: Int = 0

    func cues(for side: BattleSide) -> BattleSideCues {
        side == .player ? playerCues : opponentCues
    }

    func mutateCues(_ side: BattleSide, _ body: (inout BattleSideCues) -> Void) {
        switch side {
        case .player:   body(&playerCues)
        case .opponent: body(&opponentCues)
        }
    }

    func playEntrance() async {
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            hasEntered = true
        }
    }

    func playAttack(side: BattleSide) async {
        withAnimation(.easeOut(duration: 0.10)) { attackingSide = side }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { attackingSide = nil }
    }

    func playHit(side: BattleSide, amount: Int, effectiveness: Double) async {
        if effectiveness > 0, amount > 0 {
            mutateCues(side) { $0.shakeTick += 1 }
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    func playRecoil(side: BattleSide, amount: Int) async {
        if amount > 0 {
            mutateCues(side) { $0.shakeTick += 1 }
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    func playFaint(side: BattleSide) async {
        withAnimation(.easeIn(duration: 0.5)) { faintedSide = side }
        try? await Task.sleep(for: .milliseconds(450))
    }

    func postDamage(side: BattleSide, amount: Int) {
        guard amount > 0 else { return }
        mutateCues(side) {
            $0.damageAmount = amount
            $0.damageTick += 1
        }
    }

    /// Route a `BattleEvent` to the matching animation cue. Events that
    /// don't drive a sprite/HUD change (status text, etc.) no-op here.
    func play(_ event: BattleEvent) async {
        switch event {
        case .used(let side, _):
            await playAttack(side: side)
        case .damaged(let side, let amount, let effectiveness, _):
            await playHit(side: side, amount: amount, effectiveness: effectiveness)
        case .recoil(let side, let amount):
            await playRecoil(side: side, amount: amount)
        case .fainted(let side):
            await playFaint(side: side)
        default:
            break
        }
    }
}
