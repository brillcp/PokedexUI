import SwiftUI

/// Fixed-height scrolling battle log showing the most recent events.
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

    var assembledRows: [Row] {
        let firstVisible = max(0, log.count - Self.lineCount)
        let real: [Row] = (firstVisible..<log.count).map { ($0, log[$0]) }
        let placeholderCount = max(0, Self.lineCount - real.count)
        let placeholders: [Row] = (0..<placeholderCount).map { (-($0 + 1), AttributedString("")) }
        return placeholders + real
    }
}
