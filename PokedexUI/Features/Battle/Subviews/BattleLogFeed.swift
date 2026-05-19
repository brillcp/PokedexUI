import SwiftUI

/// Fixed-height Gameboy-style log window: always renders `lineCount` rows
/// (5 by default), showing the most recent real entries at the bottom and
/// blank placeholders pushed up off-screen above. Each real entry carries
/// its absolute index in `log` as a stable id so a fresh line animates in
/// with `.move + .opacity` instead of swapping in place; placeholders use
/// negative ids that are equally stable. When `thinking` is true a
/// reserved row at the bottom carries a distinct id so the "…" indicator
/// animates in and out without disturbing the surrounding rows.
struct BattleLogFeed: View {
    let log: [AttributedString]
    let thinking: Bool

    var body: some View {
        let rows = assembledRows
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.id) { row in
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
        .animation(.easeOut, value: thinking)
    }
}

// MARK: - Private

private extension BattleLogFeed {
    static let lineCount = 5
    static let lineHeight: CGFloat = 16
    /// Sentinel id for the thinking row. Chosen far enough from log
    /// indices (positive) and placeholders (small negatives) that
    /// SwiftUI can't accidentally match it during a diff.
    static let thinkingRowID = -9999

    typealias Row = (id: Int, text: AttributedString)

    /// Build the row list bottom-up: real log entries first, blank
    /// placeholders prepended to pad up to capacity, optional thinking
    /// row appended last.
    var assembledRows: [Row] {
        let realCapacity = thinking ? Self.lineCount - 1 : Self.lineCount
        let firstVisible = max(0, log.count - realCapacity)
        var rows: [Row] = (firstVisible..<log.count).map { ($0, log[$0]) }
        let placeholderCount = max(0, realCapacity - rows.count)
        let placeholders: [Row] = (0..<placeholderCount).map { (-($0 + 1), AttributedString("")) }
        rows = placeholders + rows
        if thinking {
            rows.append((Self.thinkingRowID, AttributedString(" ")))
        }
        return rows
    }
}
