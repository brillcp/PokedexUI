import SwiftUI
import BattleKit

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
}
