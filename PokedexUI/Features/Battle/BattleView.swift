import SwiftUI

/// Gameboy-styled turn-based battle screen. Renders the arena (sprites + HP
/// cards), a scrolling event log, and a 2x2 move grid. The view itself owns
/// no battle logic; it animates events produced by `BattleViewModel` +
/// `BattleEngine`.
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

}

// MARK: - Layout

private extension BattleView {
    @ViewBuilder
    var content: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .tint(.white)
                .font(.pixel14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .lineHeight(.loose)
        } else if let state = viewModel.state {
            battleLayout(state: state)
                .padding(.horizontal)
        }
    }

    func battleLayout(state: BattleState) -> some View {
        VStack(spacing: 12) {
            Spacer()
            arena(state: state)
            logFeed.padding(.top, 24)
            moveGrid(state: state)
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 24.0)
    }

    /// Classic Gameboy-style layout: opponent top-right with HP top-left,
    /// player bottom-left (back sprite) with HP bottom-right.
    func arena(state: BattleState) -> some View {
        VStack {
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
    /// player shows them BELOW, so each side's "id badge" sits next to the
    /// sprite it represents (opponent sprite is below its card, player sprite
    /// is above its card).
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

    /// GameBoy-style fixed window: always 5 lines tall, showing the most
    /// recent 5. Each real entry carries a stable identity (its absolute
    /// index in `log`) so a fresh line gets `.transition(.move + .opacity)`
    /// instead of swapping in place. Placeholders use negative ids (also
    /// stable) and animate out from the top as real lines push them
    /// off-screen.
    var logFeed: some View {
        let lineCount = 5
        let lineHeight: CGFloat = 16
        let thinking = viewModel.aiThinking
        let realCapacity = thinking ? lineCount - 1 : lineCount
        let logCount = viewModel.log.count
        let firstVisible = max(0, logCount - realCapacity)
        var rows: [(id: Int, text: String)] = (firstVisible..<logCount).map { ($0, viewModel.log[$0]) }
        let placeholderCount = max(0, realCapacity - rows.count)
        let placeholders: [(id: Int, text: String)] = (0..<placeholderCount).map { (-($0 + 1), "") }
        rows = placeholders + rows
        // Stable id for the thinking row, distinct from log indices and
        // placeholders so SwiftUI animates it in/out cleanly.
        if thinking {
            rows.append((-9999, "..."))
        }
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
        .animation(.easeOut(duration: 0.25), value: thinking)
    }

    func moveGrid(state: BattleState) -> some View {
        let disabled = viewModel.engine == nil || viewModel.isResolvingTurn || viewModel.winner != nil
        let spacing: CGFloat = 12
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
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 4))
                }
                .disabled(disabled)
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }

    func hpTint(current: Int, max: Int) -> Color {
        let ratio = Double(current) / Double(max)
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .yellow }
        return .red
    }

    func statusColor(_ status: BattleStatus) -> Color {
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
                    playerMoves: [
                        .init(name: "move"),
                        .init(name: "move2"),
                        .init(name: "move3"),
                        .init(name: "move4")
                    ],
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
