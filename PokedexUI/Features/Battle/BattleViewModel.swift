import SwiftUI

/// Drives `BattleView`. Takes fully-hydrated combatants and both sides'
/// finalised 4-move loadouts from `BattleSetupViewModel`. By the time we get
/// here, all preflight (hydration, move sampling, AI loadout pick) is done.
///
/// Acts as a thin conductor: engine resolves rounds, `BattleAnimator` owns
/// every cue + timing block, `BattleLogFormatter` renders log lines, audio
/// + sprite color resolution live in `BattleViewModel+Setup.swift`.
@MainActor
@Observable
final class BattleViewModel {
    let playerPokemon:   PokemonViewModel
    let opponentPokemon: PokemonViewModel
    /// Player's 4 hand-picked moves.
    let playerMoves:     [MoveDetail]
    /// Opponent's 4 AI-picked moves.
    let opponentMoves:   [MoveDetail]
    /// Owns attack / shake / faint / entrance / damage popup cues. Held as
    /// a child @Observable so `BattleView` can read animator state without
    /// pulling each cue field onto the VM surface.
    let animator: BattleAnimator
    /// Pure renderer for log lines. Holds the two combatant names; sprite
    /// colors come in per call from `animator` so the formatter has no
    /// duplicate color state to keep in sync.
    let formatter: BattleLogFormatter

    var engine: BattleEngine?
    var state:  BattleState?
    var log:    [AttributedString] = []
    var isResolvingTurn  = false
    var winner: BattleSide?
    var errorMessage: String?

    let typeChartLoader: TypeChartLoader
    let audioPlayer:     AudioPlayer
    let brain:           OpponentBrain
    let spriteLoader:    SpriteLoader
    let imageColorAnalyzer: ImageColorAnalyzer
    /// Captured Sendable snapshot of the type chart. Set once `prepare()`
    /// resolves the loader. AI service reads this off-main on every turn,
    /// with no actor hops.
    var typeChart: TypeChart?

    init(
        player: PokemonViewModel,
        opponent: PokemonViewModel,
        playerMoves: [MoveDetail],
        opponentMoves: [MoveDetail],
        container: AppContainer
    ) {
        self.playerPokemon      = player
        self.opponentPokemon    = opponent
        self.playerMoves        = playerMoves
        self.opponentMoves      = opponentMoves
        self.typeChartLoader    = container.typeChart
        self.audioPlayer        = container.audioPlayer
        self.brain              = OpponentBrain(service: container.battleAI)
        self.spriteLoader       = container.spriteLoader
        self.imageColorAnalyzer = container.imageColorAnalyzer
        self.animator           = BattleAnimator()
        self.formatter          = BattleLogFormatter(
            playerName:   player.name,
            opponentName: opponent.name
        )
        // Build the visible state immediately so the arena (HP cards, sprites,
        // log) renders on the very first frame. The engine, which actually
        // resolves rounds, only comes online once the type chart is
        // available; until then the move grid is disabled at the view level
        // via `engine == nil`.
        let p = BattleCombatant(pokemon: player,   moves: playerMoves)
        let o = BattleCombatant(pokemon: opponent, moves: opponentMoves)
        let initialState = BattleState(player: p, opponent: o)
        self.state = initialState
        // Engine fast-path: if the chart is already loaded (almost always, it
        // hydrates eagerly at app launch), wire the engine right here so the
        // move grid is tappable from frame 1.
        if let chart = container.typeChart.chart {
            activateEngine(state: initialState, chart: chart)
        }
    }

    /// Bring the engine online if it wasn't ready at init time and play the
    /// entrance animations + sprite color analysis in parallel.
    func prepare() async {
        if engine == nil {
            // Slow-path: type chart wasn't loaded at init time. Wait for it,
            // then bring the engine online.
            await typeChartLoader.loadIfNeeded()
            guard let chart = typeChartLoader.chart, let state else {
                errorMessage = "Couldn't load type chart."
                return
            }
            activateEngine(state: state, chart: chart)
        }
        async let entrance: Void = playEntrance()
        async let colors: Void = loadSpriteColors()
        _ = await (entrance, colors)
    }
}

// MARK: - Private

private extension BattleViewModel {
    /// Wire the engine + cache the chart snapshot. Single source of truth
    /// shared by the init fast-path (chart loaded eagerly at app launch)
    /// and the `prepare` slow-path (waiting on `TypeChartLoader`).
    func activateEngine(state: BattleState, chart: TypeChart) {
        self.typeChart = chart
        self.engine    = BattleEngine(state: state, typeChart: chart)
    }
}
