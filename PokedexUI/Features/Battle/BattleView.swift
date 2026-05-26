import SwiftUI
import PokeBattleKit

/// Gameboy-styled turn-based battle screen.
struct BattleView<ViewModel: BattleViewModelProtocol>: View {
    @Environment(\.container) private var container

    @State var viewModel: ViewModel

    var body: some View {
        content
            .applyPokedexStyling(title: "\(viewModel.playerName) vs \(viewModel.opponentName)", navColor: .darkGrey)
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
        VStack(spacing: 0) {
            Spacer()
            arena(state: state)
                .padding()
            BattleLogFeed(log: viewModel.log)
                .padding(.horizontal)
            moveGrid(state: state)
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 24.0)
    }

    func arena(state: BattleState) -> some View {
        VStack(spacing: 42.0) {
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

    func sprite(url: String?, side: Side) -> some View {
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

    func hpCard(_ c: Combatant, side: Side) -> some View {
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
        HStack {
            ForEach(types, id: \.self) { type in
                Chip.type(type)
            }
        }
    }

    func moveGrid(state: BattleState) -> some View {
        let disabled = !viewModel.canSelectMove || viewModel.isResolvingTurn || viewModel.winner != nil
        let opponentTypes = state.opponent.typeNames
        return LazyVGrid(columns: GridLayout.two.layout, spacing: GridLayout.two.spacing) {
            ForEach(viewModel.displayMoves, id: \.name) { move in
                let effectiveness: Double? = opponentTypes.isEmpty
                    ? nil
                    : PokeBattleKit.typeChart.multiplier(attacking: move.typeName, defenders: opponentTypes)
                Button {
                    Task { await viewModel.submit(move) }
                } label: {
                    MoveCell(move: move, mode: .battle, effectiveness: effectiveness)
                        .equatable()
                }
                .disabled(disabled)
                .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isResolvingTurn)
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
                    playerMoves: Array(PokeBattleKit.allMoves.prefix(4)),
                    opponentMoves: Array(PokeBattleKit.allMoves.prefix(4)),
                    container: .live
                )
            )
        }
        .applyPokedexStyling(title: "Battle", navColor: .darkGrey)
    }
    .colorScheme(.dark)
}
