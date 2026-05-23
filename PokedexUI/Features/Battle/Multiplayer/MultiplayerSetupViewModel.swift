import Foundation
import MultipeerConnectivity
import PokeBattleKit
import SwiftUI

/// Discrete states the multiplayer lobby moves through, from menu to ready.
enum MultiplayerSetupPhase: Equatable {
    case menu
    case hosting
    case browsing
    case connecting
    case picking
    case waitingForOpponent
    case launching
    case error(String)
}

/// Composite payload the lobby hands back to the navigation host once both
/// peers have exchanged challenges and the battle view model is wired up.
struct MultiplayerLaunch: Identifiable, Hashable {
    let id = UUID()
    let viewModel: MultiplayerBattleViewModel

    static func == (lhs: MultiplayerLaunch, rhs: MultiplayerLaunch) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Drives `MultiplayerSetupView`. Owns peer discovery, the local pokemon +
/// move selection, the wire handshake, and the assembly of the live battle
/// view model once both peers have submitted their loadouts.
@MainActor
@Observable
final class MultiplayerSetupViewModel {
    private let container: AppContainer
    private var listenTask: Task<Void, Never>?
    private var ownChallengeSent: Bool = false
    private var peerChallenge: ChallengePayload?

    let maxSelections: Int = 4
    let multipeer: MultipeerService

    var phase: MultiplayerSetupPhase = .menu
    var selectedPokemon: Pokemon?
    var movePool: [Move] = []
    var selectedMoveNames: Set<String> = []
    var selectionOrder: [String] = []
    var launch: MultiplayerLaunch?

    init(container: AppContainer) {
        self.container = container
        self.multipeer = container.multipeerService
        self.listenTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.multipeer.messages {
                await self.handle(message)
            }
        }
    }
}

// MARK: - Lobby actions
extension MultiplayerSetupViewModel {
    func startHosting() {
        multipeer.startHosting()
        phase = .hosting
    }

    func startBrowsing() {
        multipeer.startBrowsing()
        phase = .browsing
    }

    func invite(_ peer: PeerHandle) {
        multipeer.invite(peer.id)
        phase = .connecting
    }

    func acceptInvitation() {
        multipeer.acceptInvitation()
        phase = .connecting
    }

    func declineInvitation() {
        multipeer.declineInvitation()
    }

    func cancel() {
        multipeer.disconnect()
        reset()
    }

    func selectPokemon(_ pokemon: Pokemon) {
        selectedPokemon = pokemon
        movePool = Self.rankedByImpact(movesForPokemon(pokemon))
        selectedMoveNames = []
        selectionOrder = []
    }

    func toggleMove(_ move: Move) {
        if selectedMoveNames.contains(move.name) {
            selectedMoveNames.remove(move.name)
            selectionOrder.removeAll { $0 == move.name }
            return
        }
        guard selectedMoveNames.count < maxSelections else { return }
        selectedMoveNames.insert(move.name)
        selectionOrder.append(move.name)
    }

    func selectedMoves() -> [Move] {
        let byName = Dictionary(movePool.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        return selectionOrder.compactMap { byName[$0] }
    }

    /// Send the locally chosen loadout to the peer. Role determines whether
    /// the message is `.challengeProposed` (host) or `.challengeAccepted`
    /// (guest); the two are functionally identical in handling.
    func submitLoadout() {
        guard let pokemon = selectedPokemon,
              selectedMoveNames.count == maxSelections,
              let role = multipeer.role
        else { return }
        let payload = ChallengePayload(
            pokemon: PokemonSummary(pokemon: pokemon),
            moveNames: selectionOrder
        )
        switch role {
        case .host:  multipeer.send(.challengeProposed(payload))
        case .guest: multipeer.send(.challengeAccepted(payload))
        }
        ownChallengeSent = true
        phase = peerChallenge == nil ? .waitingForOpponent : .launching
        tryLaunch()
    }

    var pendingInvitation: PendingInvitation? { multipeer.pendingInvitation }

    var connectionState: MultipeerConnectionState { multipeer.connectionState }

    var discoveredPeers: [PeerHandle] {
        multipeer.discoveredPeers.map(PeerHandle.init(id:))
    }

    var isConnected: Bool { !multipeer.connectedPeers.isEmpty }
}

// MARK: - Private
private extension MultiplayerSetupViewModel {
    func handle(_ message: BattleMessage) async {
        switch message {
        case .hello(let version, _, _):
            if version != MultipeerProtocol.version {
                phase = .error("Opponent uses a different protocol version.")
                multipeer.disconnect()
            }
        case .challengeProposed(let payload), .challengeAccepted(let payload):
            peerChallenge = payload
            if phase == .waitingForOpponent || ownChallengeSent {
                phase = .launching
                tryLaunch()
            }
        case .challengeDeclined:
            phase = .error("Opponent declined the challenge.")
        case .disconnect:
            phase = .error("Opponent disconnected.")
        case .moveCommitted, .roundResolved, .battleEnded, .rematch:
            break
        }
    }

    func tryLaunch() {
        guard ownChallengeSent,
              let peerChallenge,
              let role = multipeer.role,
              let pokemon = selectedPokemon
        else { return }
        let selfMoves = selectedMoves()
        let peerMoves = peerChallenge.moveNames.compactMap { PokeBattleKit.move(named: $0) }
        guard peerMoves.count == maxSelections else {
            phase = .error("Opponent sent an invalid loadout.")
            return
        }
        let viewModel = MultiplayerBattleViewModel(
            role: role,
            selfSummary: PokemonSummary(pokemon: pokemon),
            selfMoves: selfMoves,
            peerSummary: peerChallenge.pokemon,
            peerMoves: peerMoves,
            multipeer: multipeer,
            container: container
        )
        launch = MultiplayerLaunch(viewModel: viewModel)
    }

    func reset() {
        phase = .menu
        selectedPokemon = nil
        movePool = []
        selectedMoveNames = []
        selectionOrder = []
        ownChallengeSent = false
        peerChallenge = nil
        launch = nil
    }

    func movesForPokemon(_ pokemon: Pokemon) -> [Move] {
        let names = Set(pokemon.moveNames)
        return PokeBattleKit.allMoves.filter { names.contains($0.name) && $0.isBattleReady }
    }

    static func rankedByImpact(_ moves: [Move]) -> [Move] {
        moves.sorted { lhs, rhs in
            let lDamage = (lhs.power ?? 0) > 0
            let rDamage = (rhs.power ?? 0) > 0
            if lDamage != rDamage { return lDamage }
            let lp = lhs.power ?? 0
            let rp = rhs.power ?? 0
            if lp != rp { return lp > rp }
            return (lhs.accuracy ?? 100) > (rhs.accuracy ?? 100)
        }
    }
}

/// Identifiable wrapper around `MCPeerID` for stable use in SwiftUI lists.
struct PeerHandle: Identifiable, Hashable {
    let id: MCPeerID
    var name: String { id.displayName }
}
