import SwiftUI
import PokeBattleKit

/// `BattleViewModelProtocol` implementation that runs a turn-based battle
/// across two devices over `MultipeerService`. Host runs the engine and
/// broadcasts resolved events; guest renders received events with sides
/// flipped so its own pokemon always appears as `.player`.
@MainActor
@Observable
final class MultiplayerBattleViewModel {
    private let role: MultipeerRole
    private let multipeer: MultipeerService
    private let audioPlayer: AudioPlaying
    private let formatter: BattleLogFormatter
    private let spriteColors: SpriteColorResolver
    private let selfSummary: PokemonSummary
    private let peerSummary: PokemonSummary
    private let selfMoves: [Move]
    private let peerMoves: [Move]
    private var typeChart: TypeChart?
    private var engine: BattleEngine?
    private var turnNumber: Int = 0
    private var pendingSelfMove: Move?
    private var pendingPeerMoveName: String?

    let animator: BattleAnimator
    let displayMoves: [Move]
    let playerName: String
    let opponentName: String

    var state: BattleState?
    var log: [AttributedString] = []
    var isResolvingTurn: Bool = false
    var winner: Side?
    var errorMessage: String?

    init(
        role: MultipeerRole,
        selfSummary: PokemonSummary,
        selfMoves: [Move],
        peerSummary: PokemonSummary,
        peerMoves: [Move],
        multipeer: MultipeerService,
        container: AppContainer
    ) {
        self.role = role
        self.multipeer = multipeer
        self.audioPlayer = container.audioPlayer
        self.selfSummary = selfSummary
        self.peerSummary = peerSummary
        self.selfMoves = selfMoves
        self.peerMoves = peerMoves
        self.displayMoves = selfMoves
        self.playerName = selfSummary.name
        self.opponentName = peerSummary.name
        self.animator = BattleAnimator()
        self.formatter = BattleLogFormatter(
            playerName: selfSummary.name,
            opponentName: peerSummary.name
        )
        self.spriteColors = SpriteColorResolver(
            spriteLoader: container.spriteLoader,
            imageColorAnalyzer: container.imageColorAnalyzer
        )
        let selfCombatant = Combatant(
            pokemon: selfSummary,
            moves: selfMoves.map { MoveSnapshot(from: $0) },
            hpBonus: 1.2
        )
        let peerCombatant = Combatant(
            pokemon: peerSummary,
            moves: peerMoves.map { MoveSnapshot(from: $0) },
            hpBonus: 1.2
        )
        self.state = BattleState(player: selfCombatant, opponent: peerCombatant)
        if role == .host {
            let chart = PokeBattleKit.typeChart
            self.typeChart = chart
            self.engine = BattleEngine(state: state!, typeChart: chart)
        }
    }
}

// MARK: - BattleViewModelProtocol
extension MultiplayerBattleViewModel: BattleViewModelProtocol {
    var canSelectMove: Bool {
        state != nil && pendingSelfMove == nil && winner == nil && !isResolvingTurn
    }

    func prepare() async {
        startListening()
        async let entrance: Void = playEntrance()
        async let colors: Void = spriteColors.resolve(
            playerID: selfSummary.id,
            playerSpriteURL: selfSummary.frontSprite,
            opponentID: peerSummary.id,
            opponentSpriteURL: peerSummary.frontSprite,
            animator: animator
        )
        _ = await (entrance, colors)
    }

    func submit(_ move: Move) async {
        guard canSelectMove else { return }
        animator.attackTick += 1
        pendingSelfMove = move
        turnNumber += 1
        log.append(formatter.waitingForOpponent())
        multipeer.send(.moveCommitted(moveName: move.name, turnNumber: turnNumber))
        if role == .host { await tryResolveHostTurn() }
    }
}

// MARK: - Message handling
private extension MultiplayerBattleViewModel {
    func startListening() {
        let stream = multipeer.events()
        Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .message(let message) = event {
                    await self.handle(message)
                }
            }
        }
    }

    func handle(_ message: BattleMessage) async {
        switch message {
        case .moveCommitted(let moveName, let turn):
            await receivePeerMove(name: moveName, turn: turn)
        case .roundResolved(let events, let turn):
            await receiveResolution(events: events, turn: turn)
        case .battleEnded(let w):
            self.winner = role == .host ? w : w?.opposite
        case .disconnect:
            errorMessage = "Opponent disconnected."
            winner = nil
        case .hello, .challengeProposed, .challengeAccepted, .challengeDeclined, .rematch:
            break
        }
    }

    func receivePeerMove(name: String, turn: Int) async {
        if pendingSelfMove == nil {
            log.append(formatter.chooseMove())
        }
        guard role == .host else { return }
        guard turn == turnNumber || turn == turnNumber + (pendingSelfMove == nil ? 1 : 0) else { return }
        pendingPeerMoveName = name
        await tryResolveHostTurn()
    }

    func receiveResolution(events: [Event], turn: Int) async {
        guard role == .guest else { return }
        guard turn == turnNumber else { return }
        isResolvingTurn = true
        removePromptLines()
        let flipped = events.map(flip(_:))
        await play(events: flipped)
        pendingSelfMove = nil
        isResolvingTurn = false
    }

    func tryResolveHostTurn() async {
        guard role == .host,
              let selfMove = pendingSelfMove,
              let peerName = pendingPeerMoveName,
              let peerMove = peerMoves.first(where: { $0.name == peerName }) ?? PokeBattleKit.move(named: peerName),
              var eng = engine
        else { return }
        isResolvingTurn = true
        removePromptLines()
        let events = eng.resolveRound(playerMove: selfMove, opponentMove: peerMove)
        self.engine = eng
        multipeer.send(.roundResolved(events: events, turnNumber: turnNumber))
        await play(events: events)
        pendingSelfMove = nil
        pendingPeerMoveName = nil
        state = eng.state
        isResolvingTurn = false
    }
}

// MARK: - Rendering
private extension MultiplayerBattleViewModel {
    func play(events: [Event]) async {
        for event in events {
            let line = formatter.format(
                event,
                playerColor: animator.playerCues.color,
                opponentColor: animator.opponentCues.color
            )
            log.append(line)
            apply(event)
            await animator.play(event)
            try? await Task.sleep(for: .milliseconds(650))
            if case .ended(let w) = event {
                winner = w ?? .player
                await playWinnerCry()
                if role == .host {
                    multipeer.send(.battleEnded(winner: w))
                }
                break
            }
        }
    }

    func apply(_ event: Event) {
        guard var snapshot = state else { return }
        BattleStateReducer.apply(event, to: &snapshot, animator: animator)
        state = snapshot
    }

    func playEntrance() async {
        await animator.playEntrance()
        log.append(formatter.opponentReady(opponentColor: animator.opponentCues.color))
        if let cry = peerSummary.cryURL {
            await audioPlayer.play(from: cry)
        }
    }

    func playWinnerCry() async {
        guard let winner else { return }
        let cry = winner == .player ? selfSummary.cryURL : peerSummary.cryURL
        guard let cry else { return }
        try? await Task.sleep(for: .milliseconds(350))
        await audioPlayer.play(from: cry)
    }

    func removePromptLines() {
        withAnimation(.easeOut(duration: 0.25)) {
            log.removeAll { line in
                let text = String(line.characters)
                return text.contains("Waiting for opponent") || text.contains("Pick a move")
            }
        }
    }

    func flip(_ event: Event) -> Event {
        switch event {
        case .used(let s, let m):                return .used(s.opposite, moveName: m)
        case .missed(let s):                     return .missed(s.opposite)
        case .damaged(let s, let a, let e, let c): return .damaged(s.opposite, amount: a, effectiveness: e, crit: c)
        case .statusApplied(let s, let st):      return .statusApplied(s.opposite, st)
        case .statusTick(let s, let st, let a):  return .statusTick(s.opposite, st, amount: a)
        case .statChanged(let s, let st, let d): return .statChanged(s.opposite, stat: st, delta: d)
        case .healed(let s, let a):              return .healed(s.opposite, amount: a)
        case .recoil(let s, let a):              return .recoil(s.opposite, amount: a)
        case .recharging(let s):                 return .recharging(s.opposite)
        case .wokeUp(let s):                     return .wokeUp(s.opposite)
        case .fastAsleep(let s):                 return .fastAsleep(s.opposite)
        case .fullyParalyzed(let s):             return .fullyParalyzed(s.opposite)
        case .lostFocus(let s):                  return .lostFocus(s.opposite)
        case .fainted(let s):                    return .fainted(s.opposite)
        case .ended(let w):                      return .ended(winner: w?.opposite)
        }
    }
}
