import SwiftUI

/// Fixed-height Gameboy-style log window: always renders `lineCount` rows
/// (5 by default), showing the most recent real entries at the bottom and
/// blank placeholders pushed up off-screen above. Each real entry carries
/// its absolute index in `log` as a stable id so a fresh line animates in
/// with `.move + .opacity` instead of swapping in place; placeholders use
/// negative ids that are equally stable.
struct BattleLogFeed: View {
    let log: [AttributedString]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(assembledRows, id: \.id) { row in
                Text(row.text)
                    .font(.pixel12)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: Self.lineHeight, alignment: .leading)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeOut, value: log.count)
    }
}

// MARK: - Private

private extension BattleLogFeed {
    static let lineCount = 5
    static let lineHeight: CGFloat = 16

    typealias Row = (id: Int, text: AttributedString)

    /// Build the row list bottom-up: real log entries first, blank
    /// placeholders prepended to pad up to capacity.
    var assembledRows: [Row] {
        let firstVisible = max(0, log.count - Self.lineCount)
        let real: [Row] = (firstVisible..<log.count).map { ($0, log[$0]) }
        let placeholderCount = max(0, Self.lineCount - real.count)
        let placeholders: [Row] = (0..<placeholderCount).map { (-($0 + 1), AttributedString("")) }
        return placeholders + real
    }
}
