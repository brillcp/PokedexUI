import SwiftUI

/// One combatant's sprite. Owns the celebration tilt state so the rotation can
/// repeat indefinitely after victory without leaking a `Timer` into the view
/// model. Lunge / shake / faint cues read off plain Bool/Int props pushed in
/// by the parent BattleView.
struct BattlerSprite: View {
    let url: String?
    let side: BattleSide
    let isAttacking: Bool
    let isFainted: Bool
    let hasEntered: Bool
    let shakeTick: Int
    let damageAmount: Int?
    let damageTick: Int
    let isWinner: Bool

    @State private var celebratingTilt: Double = 0

    /// Off-screen entry: player from left (negative), opponent from right (positive).
    /// Faint slide: player flies further off-left, opponent off-right.
    private var entryOffset: CGFloat {
        if isFainted {
            return side == .player ? -200 : 200
        }
        return hasEntered ? 0 : (side == .player ? -200 : 200)
    }

    /// Attack lunge toward the opponent. Player lunges up-right, opponent down-left.
    private var lungeOffset: CGSize {
        guard isAttacking else { return .zero }
        return side == .player
            ? CGSize(width: 20, height: -10)
            : CGSize(width: -20, height: 10)
    }

    /// Slight horizontal nudge so the "-N" label doesn't sit dead-center
    /// over the sprite's head. Player nudges right, opponent nudges left
    /// so the popup mirrors the lunge direction on either side.
    private var damagePopupOffset: CGSize {
        side == .player
            ? CGSize(width: 22, height: 36)
            : CGSize(width: -22, height: 36)
    }

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Color(.systemGray4).clipShape(Circle())
        }
        .frame(width: 120, height: 148)
        .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
        .rotationEffect(.degrees(celebratingTilt))
        .offset(
            x: lungeOffset.width + entryOffset,
            y: lungeOffset.height
        )
        .opacity(isFainted ? 0 : 1)
        .overlay(alignment: .top) { damagePopup }
        .animation(.easeOut(duration: 0.6), value: damageTick)
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: shakeTick)
        .animation(.easeOut(duration: 0.5), value: isFainted)
        .onChange(of: isWinner) { _, newValue in
            if newValue {
                withAnimation(.bouncy(duration: 0.35).repeatForever(autoreverses: true)) {
                    celebratingTilt = 10
                }
            } else {
                withAnimation { celebratingTilt = 0 }
            }
        }
    }
}

// MARK: - Damage popup

private extension BattlerSprite {
    /// Floating "-N" pop over the sprite. Keyed by `damageTick` so two
    /// hits in a row with the same amount still retrigger: `.id(...)`
    /// makes SwiftUI tear down the old view (with its removal transition)
    /// and insert a fresh one (with its insertion transition). The
    /// surrounding `.animation(_:value: damageTick)` on the sprite is
    /// what makes those transitions actually animate instead of snapping.
    @ViewBuilder
    var damagePopup: some View {
        if let amount = damageAmount, damageTick > 0 {
            DamagePopup(amount: amount, offset: damagePopupOffset)
                .id(damageTick)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 24)),
                        removal: .opacity.combined(with: .offset(y: -24))
                    )
                )
        }
    }
}

/// Floating "-N" label rendered above the sprite. Stateless: position +
/// fade are driven entirely by the parent's `.transition`, which the
/// `.animation(_:value: damageTick)` on `BattlerSprite` brings to life
/// every time a new tick replaces the previous label.
private struct DamagePopup: View {
    let amount: Int
    let offset: CGSize

    var body: some View {
        Text("-\(amount)")
            .font(.pixel14)
            .foregroundStyle(Color.pokedexRed)
            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
            .offset(offset)
    }
}
