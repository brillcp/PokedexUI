import Foundation
import MultipeerConnectivity
import SwiftUI

/// Lightweight invitation handle for SwiftUI alert presentation.
struct PendingInvitation: Identifiable, Equatable {
    let id = UUID()
    let peerName: String
}

/// Role this device plays in the session. Advertiser = `.host`, browser =
/// `.guest`. Decided at the moment a peer chooses to host or browse.
enum MultipeerRole: Sendable {
    case host
    case guest
}

/// Typed events emitted by MultipeerConnectivity delegate callbacks.
/// Consumed by view models via the `events()` AsyncStream.
enum MultipeerEvent {
    case peerFound(MCPeerID)
    case peerLost(MCPeerID)
    case peerConnecting(MCPeerID)
    case peerConnected(MCPeerID)
    case peerDisconnected(MCPeerID)
    case invitationReceived(peerName: String)
    case advertisingFailed(Error)
    case browsingFailed(Error)
    case message(BattleMessage)
}

/// Process-wide MultipeerConnectivity wrapper. Owns the `MCSession`,
/// advertiser, and browser; emits typed `MultipeerEvent`s via AsyncStream
/// for consumption by view models.
@Observable
final class MultipeerService: NSObject {
    private static let serviceType = "pokedex-vs"

    private var subscribers: [UUID: AsyncStream<MultipeerEvent>.Continuation] = [:]
    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitationHandler: ((Bool) -> Void)?

    private(set) var role: MultipeerRole?
    var localDisplayName: String { myPeerID.displayName }

    override init() {
        let name = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: name.isEmpty ? "Trainer" : name)
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        self.session.delegate = self
    }

    /// Return a new `AsyncStream` that receives all future events. Each
    /// subscriber gets its own copy (broadcast). The stream auto-unregisters
    /// on termination so callers don't need to manually unsubscribe.
    func events() -> AsyncStream<MultipeerEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.subscribers.removeValue(forKey: id)
                }
            }
        }
    }

    /// Advertise and browse simultaneously so both devices see each other
    /// immediately. Role is decided when a connection is established: the
    /// device that sent the invite becomes `.guest`, the one that accepted
    /// becomes `.host`.
    func startDiscovery() {
        stopDiscovery()
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    /// Stop both advertising and browsing. Safe to call when neither is active.
    func stopDiscovery() {
        stopHosting()
        stopBrowsing()
    }

    /// Stop advertising. Safe to call when not hosting.
    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
    }

    /// Stop browsing. Safe to call when not browsing.
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
    }

    /// Send an invite to a discovered peer. The inviter becomes the guest.
    func invite(_ peer: MCPeerID) {
        guard let browser else { return }
        role = .guest
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    /// Accept the latest pending invitation. The accepter becomes the host.
    func acceptInvitation() {
        role = .host
        invitationHandler?(true)
        invitationHandler = nil
    }

    /// Decline the latest pending invitation.
    func declineInvitation() {
        invitationHandler?(false)
        invitationHandler = nil
    }

    /// Send a typed message to all connected peers. Encoding or transport
    /// failures are logged but not thrown; the receive stream's `.disconnect`
    /// path covers loss-of-peer recovery.
    func send(_ message: BattleMessage) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            #if DEBUG
            print("MultipeerService.send error: \(error)")
            #endif
        }
    }

    /// Tear down the session and all discovery. Idempotent.
    func disconnect() {
        send(.disconnect)
        stopDiscovery()
        session.disconnect()
        role = nil
    }
}

// MARK: - Private
private extension MultipeerService {
    func emit(_ event: MultipeerEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            stopDiscovery()
            emit(.peerConnected(peerID))
        case .connecting:
            emit(.peerConnecting(peerID))
        case .notConnected:
            emit(.peerDisconnected(peerID))
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(BattleMessage.self, from: data) else {
            #if DEBUG
            print("MultipeerService: dropped undecodable payload (\(data.count) bytes)")
            #endif
            return
        }
        emit(.message(message))
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let session = session
        self.invitationHandler = { accepted in
            invitationHandler(accepted, accepted ? session : nil)
        }
        emit(.invitationReceived(peerName: peerID.displayName))
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        emit(.advertisingFailed(error))
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        emit(.peerFound(peerID))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        emit(.peerLost(peerID))
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        emit(.browsingFailed(error))
    }
}
