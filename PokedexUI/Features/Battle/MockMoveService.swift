#if DEBUG
import Foundation

/// Returns canned `MoveDetail` instances so SwiftUI previews don't hit the
/// network. Used by `BattleView`'s `#Preview` and any future battle-related
/// tests. `#if DEBUG`-gated so it never ships in the release binary.
struct MockMoveService: MoveServiceProtocol {
    func requestMove(named name: String) async throws -> MoveDetail {
        Self.make(name)
    }

    func requestMoves(named names: [String]) async throws -> [MoveDetail] {
        names.map(Self.make)
    }

    private static func make(_ name: String) -> MoveDetail {
        let move = MoveDetail(name: name)
        move.power = 40
        move.accuracy = 100
        move.pp = 25
        move.priority = 0
        move.typeName = "normal"
        move.damageClass = "physical"
        return move
    }
}
#endif
