import SwiftUI
import PokeBattleKit

/// Drives `BattleView` as a conductor over engine, animator, log, and audio.
@MainActor
protocol BattleViewModelProtocol: AnyObject {
    var playerPokemon: PokemonViewModel { get }
    var opponentPokemon: PokemonViewModel { get }
    var animator: BattleAnimator { get }
    var state: BattleState? { get }
    var engine: Engine? { get }
    var log: [AttributedString] { get }
    var isResolvingTurn: Bool { get }
    var winner: Side? { get }
    var errorMessage: String? { get }
    var displayMoves: [Move] { get }

    func prepare() async
    func submit(_ move: Move) async
}

/// Concrete `BattleViewModelProtocol` implementation.
@MainActor
@Observable
final class BattleViewModel {
    private let opponentMoves: [Move]
    private let playerMoves:   [Move]
    private let formatter:     BattleLogFormatter
    private let audioPlayer:   AudioPlaying
    private let aiDriver:      BattleAIDriver
    private let spriteColors:  SpriteColorResolver
    private var typeChart:     TypeChart?

    let playerPokemon:   PokemonViewModel
    let opponentPokemon: PokemonViewModel
    let animator:        BattleAnimator
    let displayMoves:    [Move]

    var engine: Engine?
    var state:  BattleState?
    var log:    [AttributedString] = []
    var isResolvingTurn  = false
    var winner: Side?
    var errorMessage: String?

    init(
        player: PokemonViewModel,
        opponent: PokemonViewModel,
        playerMoves: [Move],
        opponentMoves: [Move],
        container: AppContainer
    ) {
        self.playerPokemon   = player
        self.opponentPokemon = opponent
        self.displayMoves    = playerMoves
        self.playerMoves     = playerMoves
        self.opponentMoves   = opponentMoves
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
        let p = Combatant(pokemon: player,   moves: playerMoves.map { MoveSnapshot(from: $0) }, hpBonus: 1.2)
        let o = Combatant(pokemon: opponent, moves: opponentMoves.map { MoveSnapshot(from: $0) })
        let initialState = BattleState(player: p, opponent: o)
        self.state = initialState
        let chart = PokeBattleKit.typeChart
        activateEngine(state: initialState, chart: chart)
    }
}

// MARK: - BattleViewModelProtocol
extension BattleViewModel: BattleViewModelProtocol {

    func prepare() async {
        async let entrance: Void = playEntrance()
        async let colors: Void = spriteColors.resolve(
            player: playerPokemon, opponent: opponentPokemon, animator: animator
        )
        _ = await (entrance, colors)
    }

    func submit(_ move: Move) async {
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
        self.engine    = Engine(state: state, typeChart: chart)
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

    func apply(_ event: Event) {
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
            mutate(side, in: &snapshot) { $0.status = Status.none; $0.sleepTurns = 0 }
        case .statChanged(let side, let stat, let delta):
            mutate(side, in: &snapshot) { $0.applyStage(stat, delta: delta) }
        case .used, .missed, .fullyParalyzed, .fastAsleep, .recharging, .lostFocus, .fainted, .ended:
            break
        }
        state = snapshot
    }

    func mutate(_ side: Side, in state: inout BattleState, _ body: (inout Combatant) -> Void) {
        if side == .player {
            body(&state.player)
        } else {
            body(&state.opponent)
        }
    }
}
