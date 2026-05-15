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

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Color(.systemGray4).clipShape(Circle())
        }
        .frame(width: 120, height: 148)
//        .padding()
        .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
        .rotationEffect(.degrees(celebratingTilt))
        .offset(
            x: lungeOffset.width + entryOffset,
            y: lungeOffset.height
        )
        .opacity(isFainted ? 0 : 1)
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
