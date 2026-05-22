import SwiftUI
import BattleKit

/// Drives `BattleView` as a conductor over engine, animator, log, and audio.
@MainActor
protocol BattleViewModelProtocol: AnyObject {
    /// Player-side Pokemon view model used for sprites, name, types, and cries.
    var playerPokemon: PokemonViewModel { get }
    /// Opponent-side Pokemon view model used for sprites, name, types, and cries.
    var opponentPokemon: PokemonViewModel { get }
    /// Animation cue coordinator the view binds to for sprite, HP, and shake state.
    var animator: BattleAnimator { get }
    /// Current battle state mirror updated after each resolved event;
    /// `nil` until `prepare()` activates the engine.
    var state: BattleState? { get }
    /// Turn resolver; `nil` until the type chart has loaded.
    var engine: BattleEngine? { get }
    /// Formatted log rows shown in `BattleLogFeed`, appended once per event.
    var log: [AttributedString] { get }
    /// `true` while a round is being resolved so the move grid disables.
    var isResolvingTurn: Bool { get }
    /// Winning side once the battle ends; `nil` while play continues.
    var winner: BattleSide? { get }
    /// User-facing error surfaced by `prepare()` (e.g. type chart load failure).
    var errorMessage: String? { get }
    /// Player's moves rendered in the move grid.
    var displayMoves: [MoveDetail] { get }

    /// Warm up battle state, sprite colors, and entrance animation.
    func prepare() async
    /// Submit a player move and resolve the round.
    func submit(_ move: MoveDetail) async
}

/// Concrete `BattleViewModelProtocol` implementation. Owns engine + log;
/// AI bookkeeping lives in `BattleAIDriver` and sprite/animation routing
/// lives on `BattleAnimator`.
@MainActor
@Observable
final class BattleViewModel {
    private let opponentMoves:   [MoveDetail]
    private let playerMoves:     [MoveDetail]
    private let formatter:       BattleLogFormatter
    private let typeChartLoader: TypeChartLoader
    private let audioPlayer:     AudioPlaying
    private let aiDriver:        BattleAIDriver
    private let spriteColors:    SpriteColorResolver
    private var typeChart:       TypeChart?

    let playerPokemon:   PokemonViewModel
    let opponentPokemon: PokemonViewModel
    let animator:        BattleAnimator
    let displayMoves:    [MoveDetail]

    var engine: BattleEngine?
    var state:  BattleState?
    var log:    [AttributedString] = []
    var isResolvingTurn  = false
    var winner: BattleSide?
    var errorMessage: String?

    init(
        player: PokemonViewModel,
        opponent: PokemonViewModel,
        playerMoves: [MoveDetail],
        opponentMoves: [MoveDetail],
        container: AppContainer
    ) {
        self.playerPokemon   = player
        self.opponentPokemon = opponent
        self.displayMoves    = playerMoves
        self.playerMoves     = playerMoves
        self.opponentMoves   = opponentMoves
        self.typeChartLoader = container.typeChart
        self.audioPlayer     = container.audioPlayer
        self.aiDriver        = BattleAIDriver(service: container.battleAI)
        self.spriteColors    = SpriteColorResolver(
            spriteLoader:       container.spriteLoader,
            imageColorAnalyzer: container.imageColorAnalyzer
        )
        self.animator        = BattleAnimator()
        self.formatter       = BattleLogFormatter(
            playerName:   player.name,
            opponentName: opponent.name
        )
        let p = BattleCombatant(pokemon: player,   moves: playerMoves.map { $0.snapshot() }, hpBonus: 1.2)
        let o = BattleCombatant(pokemon: opponent, moves: opponentMoves.map { $0.snapshot() })
        let initialState = BattleState(player: p, opponent: o)
        self.state = initialState
        if let chart = container.typeChart.chart {
            activateEngine(state: initialState, chart: chart)
        }
    }
}

// MARK: - BattleViewModelProtocol
extension BattleViewModel: BattleViewModelProtocol {

    func prepare() async {
        if engine == nil {
            await typeChartLoader.loadIfNeeded()
            guard let chart = typeChartLoader.chart, let state else {
                errorMessage = "Couldn't load type chart."
                return
            }
            activateEngine(state: state, chart: chart)
        }
        async let entrance: Void = playEntrance()
        async let colors: Void = spriteColors.resolve(
            player: playerPokemon, opponent: opponentPokemon, animator: animator
        )
        _ = await (entrance, colors)
    }

    func submit(_ move: MoveDetail) async {
        guard var eng = engine, let typeChart, !isResolvingTurn, winner == nil, let snapshot = state else { return }
        animator.attackTick += 1
        isResolvingTurn = true

        let opponentMove = await aiDriver.nextOpponentMove(
            attacker:      snapshot.opponent,
            defender:      snapshot.player,
            opponentMoves: opponentMoves,
            playerMoves:   playerMoves,
            typeChart:     typeChart
        )
        let events = eng.resolveRound(playerMove: move, opponentMove: opponentMove)
        self.engine = eng

        for event in events {
            let line = formatter.format(event, playerColor: animator.playerCues.color, opponentColor: animator.opponentCues.color)
            log.append(line)
            #if DEBUG
            print("⚔️ \(String(line.characters))")
            #endif
            apply(event)
            await animator.play(event)
            try? await Task.sleep(for: .milliseconds(650))
            if case .ended(let w) = event {
                winner = w ?? .player
                await playWinnerCry()
                break
            }
        }
        state = eng.state
        aiDriver.recordPlayerUsed(move.name, in: events)
        isResolvingTurn = false
    }
}

// MARK: - Private
private extension BattleViewModel {

    func activateEngine(state: BattleState, chart: TypeChart) {
        self.typeChart = chart
        self.engine    = BattleEngine(state: state, typeChart: chart)
    }

    func playEntrance() async {
        await animator.playEntrance()
        if let cry = opponentPokemon.latestCry {
            await audioPlayer.play(from: cry)
        }
    }

    func playWinnerCry() async {
        guard let winner else { return }
        let cry = winner == .player ? playerPokemon.latestCry : opponentPokemon.latestCry
        guard let cry else { return }
        try? await Task.sleep(for: .milliseconds(350))
        await audioPlayer.play(from: cry)
    }

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
        case .used, .missed, .fullyParalyzed, .fastAsleep, .recharging, .lostFocus, .fainted, .ended:
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
}
