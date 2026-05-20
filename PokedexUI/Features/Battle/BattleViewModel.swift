import SwiftUI

/// Drives `BattleView` as a conductor over engine, animator, log, and audio.
@MainActor
@Observable
final class BattleViewModel {
    let playerPokemon:   PokemonViewModel
    let opponentPokemon: PokemonViewModel
    let playerMoves:     [MoveDetail]
    let opponentMoves:   [MoveDetail]
    let animator: BattleAnimator
    let formatter: BattleLogFormatter

    var engine: BattleEngine?
    var state:  BattleState?
    var log:    [AttributedString] = []
    var isResolvingTurn  = false
    var winner: BattleSide?
    var errorMessage: String?

    let typeChartLoader: TypeChartLoader
    let audioPlayer:     AudioPlaying
    let brain:           OpponentBrain
    let spriteLoader:    SpriteLoading
    let imageColorAnalyzer: ImageColorAnalyzing
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
        let p = BattleCombatant(pokemon: player,   moves: playerMoves)
        let o = BattleCombatant(pokemon: opponent, moves: opponentMoves)
        let initialState = BattleState(player: p, opponent: o)
        self.state = initialState
        if let chart = container.typeChart.chart {
            activateEngine(state: initialState, chart: chart)
        }
    }

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
        async let colors: Void = loadSpriteColors()
        _ = await (entrance, colors)
    }
}

private extension BattleViewModel {
    func activateEngine(state: BattleState, chart: TypeChart) {
        self.typeChart = chart
        self.engine    = BattleEngine(state: state, typeChart: chart)
    }
}
