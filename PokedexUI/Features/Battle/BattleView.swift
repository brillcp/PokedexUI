import SwiftUI

struct BattleView: View {
    @State var viewModel: BattleViewModel

    var body: some View {
        content
            .foregroundStyle(.white)
            .background(Color.darkGrey.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(viewModel.playerPokemon.name) vs \(viewModel.opponentPokemon.name)")
                        .font(.pixel17)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Color.darkGrey ?? .black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.prepare() }
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.attackTick)
            .sensoryFeedback(.success, trigger: viewModel.opponentShakeTick)
            .sensoryFeedback(.error, trigger: viewModel.playerShakeTick)
            .sensoryFeedback(trigger: viewModel.winner) { _, new in
                switch new {
                case .player: return .success
                case .opponent: return .error
                case .none: return nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingMoves {
            ProgressView("Loading moves…")
                .tint(.white)
                .font(.pixel14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .lineHeight(.loose)
        } else if let error = viewModel.errorMessage {
            Text(error)
                .tint(.white)
                .font(.pixel14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .lineHeight(.loose)
        } else if let state = viewModel.state {
            battleLayout(state: state)
        }
    }

    private func battleLayout(state: BattleState) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            arena(state: state)
                .padding(.horizontal, 16)
            logFeed
                .padding(.horizontal, 16)
            moveGrid(state: state)
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 24.0)
    }

    /// Classic Gameboy-style layout: opponent top-right with HP top-left,
    /// player bottom-left (back sprite) with HP bottom-right.
    private func arena(state: BattleState) -> some View {
        VStack(spacing: -28) {
            HStack(alignment: .top) {
                hpCard(state.opponent, side: .opponent)
                Spacer(minLength: 12)
                sprite(url: state.opponent.frontSpriteURL, side: .opponent)
            }
            HStack(alignment: .bottom) {
                sprite(url: playerSpriteURL(state: state), side: .player)
                Spacer(minLength: 12)
                hpCard(state.player, side: .player)
            }
        }
    }

    private func playerSpriteURL(state: BattleState) -> String? {
        if viewModel.winner == .player {
            return state.player.frontSpriteURL
        }
        return state.player.backSpriteURL ?? state.player.frontSpriteURL
    }

    private func sprite(url: String?, side: BattleSide) -> some View {
        BattlerSprite(
            url: url,
            side: side,
            isAttacking: viewModel.attackingSide == side,
            isFainted: viewModel.faintedSide == side,
            hasEntered: viewModel.hasEntered,
            shakeTick: side == .player ? viewModel.playerShakeTick : viewModel.opponentShakeTick,
            isWinner: viewModel.winner == side
        )
    }

    /// HP card with type chips. Opponent shows chips ABOVE the glass card,
    /// player shows them BELOW — so each side's "id badge" sits next to the
    /// sprite it represents (opponent sprite is below its card, player sprite
    /// is above its card).
    private func hpCard(_ c: BattleCombatant, side: BattleSide) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

    private func typeChips(_ types: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(types, id: \.self) { type in
                Chip(
                    type.uppercased(),
                    style: .custom(background: TypeColor.color(for: type))
                )
            }
        }
    }

    /// GameBoy-style fixed window — always 5 lines tall, showing the most recent 5.
    /// Each real entry carries a stable identity (its absolute index in `log`)
    /// so a fresh line gets `.transition(.move + .opacity)` instead of swapping
    /// in place. Placeholders use negative ids — also stable — and animate out
    /// from the top as real lines push them off-screen.
    private var logFeed: some View {
        let lineCount = 5
        let lineHeight: CGFloat = 16
        let logCount = viewModel.log.count
        let firstVisible = max(0, logCount - lineCount)
        let visible: [(id: Int, text: String)] = (firstVisible..<logCount).map { ($0, viewModel.log[$0]) }
        let placeholderCount = max(0, lineCount - visible.count)
        let placeholders: [(id: Int, text: String)] = (0..<placeholderCount).map { (-($0 + 1), "") }
        let rows = placeholders + visible
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.id) { row in
                Text(row.text)
                    .font(.pixel12)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: lineHeight, alignment: .leading)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: logCount)
    }

    private func moveGrid(state: BattleState) -> some View {
        let disabled = viewModel.isResolvingTurn || viewModel.winner != nil
        let spacing: CGFloat = 12
        // Player has exactly 4 hand-picked moves (set during loadout), so the
        // grid is a static 2×2 — no scrolling needed.
        let columns = [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing)
        ]
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(state.player.moves, id: \.name) { move in
                Button {
                    Task { await viewModel.submit(move) }
                } label: {
                    MoveCell(move: move, mode: .battle)
                        .equatable()
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(disabled)
            }
        }
        .padding(.horizontal, 16)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }

    private func hpTint(current: Int, max: Int) -> Color {
        let ratio = Double(current) / Double(max)
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .yellow }
        return .red
    }

    private func statusColor(_ status: BattleStatus) -> Color {
        switch status {
        case .paralysis: return .yellow
        case .burn: return .orange
        case .poison: return .purple
        case .none: return .clear
        }
    }

}

#Preview {
    NavigationStack {
        TabView {
            BattleView(
                viewModel: BattleViewModel(
                    player: PokemonViewModel(pokemon: .pikachu),
                    opponent: PokemonViewModel(pokemon: .pikachu),
                    playerMoves: [],
                    opponentMoves: [],
                    typeChart: TypeChartLoader(),
                    audioPlayer: AudioPlayer(),
                    aiService: BattleAIService()
                )
            )
        }
    }
    .colorScheme(.dark)
}
