import SwiftUI

/// Bundle of per-side animation cues read by `BattlerSprite` and the
/// colored battle log. Lives next to the `BattleAnimator` that mutates it
/// so a sprite reading `animator.cues(for: side)` lands in one observation
/// site instead of fanning out across four properties per side.
struct BattleSideCues: Equatable {
    /// Bumped on each landed hit so SwiftUI re-runs the shake even when
    /// two identical-value hits land back-to-back.
    var shakeTick: Int = 0
    /// Latest hit amount. Drives the floating "-N" overlay over the sprite.
    var damageAmount: Int?
    /// Bumped alongside `damageAmount`; the popup's `.id(...)` reads this
    /// so the fade-up re-fires even when the new amount matches the old.
    var damageTick: Int = 0
    /// Dominant sprite color resolved once during `prepare`. Tints the
    /// pokemon's name in the battle log; `nil` until loaded.
    var color: Color?
}

/// Owns every animation cue the battle UI reads: attacker lunge, defender
/// shake, faint slide, entrance, damage popups, and the per-side cue
/// bundle. Split out of `BattleViewModel` so the view model is left as a
/// thin conductor over engine + log + audio, while this type concentrates
/// the timing constants and `withAnimation` blocks that drive the arena.
@MainActor
@Observable
final class BattleAnimator {
    /// Side currently mid-lunge, or `nil` when no attack animation is active.
    var attackingSide: BattleSide?
    /// Side currently fading off-stage on faint, or `nil` while both are upright.
    var faintedSide: BattleSide?
    /// `false` while sprites are off-stage on first appear. Flipped to `true`
    /// shortly after the entrance sequence runs.
    var hasEntered: Bool = false
    /// Per-side cue bundle. Mutate through `mutateCues(_:_:)` and read
    /// through `cues(for:)`.
    var playerCues:   BattleSideCues = BattleSideCues()
    var opponentCues: BattleSideCues = BattleSideCues()

    /// Cue bundle for one side. Used by `BattleView` so sprites resolve
    /// their own cues without per-side ternaries at the call site.
    func cues(for side: BattleSide) -> BattleSideCues {
        side == .player ? playerCues : opponentCues
    }

    /// In-place cue mutator. Goes through the property setter so
    /// `@Observable` observers see the write.
    func mutateCues(_ side: BattleSide, _ body: (inout BattleSideCues) -> Void) {
        switch side {
        case .player:   body(&playerCues)
        case .opponent: body(&opponentCues)
        }
    }

    /// Flip sprites from off-stage to on-stage after a short pause so the
    /// arena settles before the first move is picked.
    func playEntrance() async {
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            hasEntered = true
        }
    }

    /// Lunge the attacker forward then snap back. Called once per `.used`
    /// event regardless of whether the move connects.
    func playAttack(side: BattleSide) async {
        withAnimation(.easeOut(duration: 0.10)) { attackingSide = side }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { attackingSide = nil }
    }

    /// Shake the defender when a damaging hit lands. Zero-effectiveness
    /// ("had no effect") and zero-amount events skip the shake so the
    /// defender doesn't flinch on an immune hit.
    func playHit(side: BattleSide, amount: Int, effectiveness: Double) async {
        if effectiveness > 0, amount > 0 {
            mutateCues(side) { $0.shakeTick += 1 }
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    /// Shake the attacker on recoil damage (Brave Bird, Double-Edge, etc.).
    func playRecoil(side: BattleSide, amount: Int) async {
        if amount > 0 {
            mutateCues(side) { $0.shakeTick += 1 }
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    /// Fade-out + slide-off the fainting side.
    func playFaint(side: BattleSide) async {
        withAnimation(.easeIn(duration: 0.5)) { faintedSide = side }
        try? await Task.sleep(for: .milliseconds(450))
    }

    /// Surface the latest damage so the sprite can pop a floating "-N"
    /// label. Bumping the tick counter forces SwiftUI to re-fire the
    /// transition even when the previous amount matches the new one.
    func postDamage(side: BattleSide, amount: Int) {
        guard amount > 0 else { return }
        mutateCues(side) {
            $0.damageAmount = amount
            $0.damageTick += 1
        }
    }
}
