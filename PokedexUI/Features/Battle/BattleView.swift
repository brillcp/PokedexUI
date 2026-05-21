import SwiftUI
import BattleKit

/// Gameboy-styled turn-based battle screen.
struct BattleView<ViewModel: BattleViewModelProtocol>: View {
    @Environment(\.container) private var container

    @State var viewModel: ViewModel

    var body: some View {
        content
            .applyPokedexStyling(title: "\(viewModel.playerPokemon.name) vs \(viewModel.opponentPokemon.name)", color: .darkGrey)
            .foregroundStyle(.white)
            .task { await viewModel.prepare() }
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.animator.attackTick)
            .sensoryFeedback(.success, trigger: viewModel.animator.opponentCues.shakeTick)
            .sensoryFeedback(.error, trigger: viewModel.animator.playerCues.shakeTick)
            .sensoryFeedback(trigger: viewModel.winner) { _, new in
                switch new {
                case .player: return .success
                case .opponent: return .error
                case .none: return nil
                }
            }
    }

}

// MARK: - Private
private extension BattleView {
    @ViewBuilder
    var content: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .foregroundStyle(.secondary)
                .font(.pixel14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .lineHeight(.loose)
        } else if let state = viewModel.state {
            battleLayout(state: state)
        }
    }

    func battleLayout(state: BattleState) -> some View {
        VStack(spacing: 12) {
            Spacer()
            arena(state: state)
                .padding(.horizontal)
            BattleLogFeed(log: viewModel.log)
                .padding(.vertical)
                .padding(.horizontal)
            moveGrid(state: state)
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 24.0)
    }

    func arena(state: BattleState) -> some View {
        VStack(spacing: 48.0) {
            HStack(alignment: .top) {
                hpCard(state.opponent, side: .opponent)
                Spacer(minLength: 28)
                sprite(url: state.opponent.frontSpriteURL, side: .opponent)
                    .padding(.horizontal)
            }
            HStack(alignment: .bottom) {
                sprite(url: playerSpriteURL(state: state), side: .player)
                    .padding(.horizontal)
                Spacer(minLength: 28)
                hpCard(state.player, side: .player)
            }
        }
    }

    func playerSpriteURL(state: BattleState) -> String? {
        if viewModel.winner == .player {
            return state.player.frontSpriteURL
        }
        return state.player.backSpriteURL ?? state.player.frontSpriteURL
    }

    func sprite(url: String?, side: BattleSide) -> some View {
        let animator = viewModel.animator
        let cues = animator.cues(for: side)
        return BattlerSprite(
            url: url,
            side: side,
            isAttacking: animator.attackingSide == side,
            isFainted: animator.faintedSide == side,
            hasEntered: animator.hasEntered,
            shakeTick: cues.shakeTick,
            damageAmount: cues.damageAmount,
            damageTick: cues.damageTick,
            isWinner: viewModel.winner == side
        )
    }

    func hpCard(_ c: BattleCombatant, side: BattleSide) -> some View {
        VStack(alignment: side == .opponent ? .leading : .trailing, spacing: 8) {
            if side == .opponent {
                typeChips(c.typeNames)
            }
            HPCard(
                name: c.name,
                currentHP: c.currentHP,
                maxHP: c.maxHP,
                status: c.status
            )
            .equatable()
            if side == .player {
                typeChips(c.typeNames)
            }
        }
    }

    func typeChips(_ types: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(types, id: \.self) { type in
                Chip(
                    type.uppercased(),
                    style: .custom(background: TypeColor.color(for: type))
                )
            }
        }
    }

    func moveGrid(state: BattleState) -> some View {
        let disabled = viewModel.engine == nil || viewModel.isResolvingTurn || viewModel.winner != nil
        let spacing: CGFloat = 2
        let columns = [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing)
        ]
        let opponentTypes = state.opponent.typeNames
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(viewModel.displayMoves, id: \.name) { move in
                let effectiveness: Double? = opponentTypes.isEmpty
                    ? nil
                    : container.typeChart.multiplier(attacking: move.typeName, defenders: opponentTypes)
                Button {
                    Task { await viewModel.submit(move) }
                } label: {
                    MoveCell(move: move, mode: .battle, effectiveness: effectiveness)
                        .equatable()
                }
                .disabled(disabled)
            }
        }
        .disabled(disabled)
        .opacity(disabled ? Opacity.disabled : 1)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }

}


#Preview {
    NavigationStack {
        TabView {
            BattleView(
                viewModel: BattleViewModel(
                    player: PokemonViewModel(pokemon: .pikachu),
                    opponent: PokemonViewModel(pokemon: .pikachu),
                    playerMoves: [
                        .init(name: "move"),
                        .init(name: "move2"),
                        .init(name: "move3"),
                        .init(name: "move4")
                    ],
                    opponentMoves: [],
                    container: .live
                )
            )
        }
        .applyPokedexStyling(title: "Battle", color: .darkGrey)
    }
    .colorScheme(.dark)
}
