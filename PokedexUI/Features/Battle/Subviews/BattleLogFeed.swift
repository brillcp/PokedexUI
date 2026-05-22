import SwiftUI

/// Scrollable battle log pinned to the latest event, with a fade/shrink
/// effect on the top row so the player can scroll back through history.
struct BattleLogFeed: View {
    let log: [AttributedString]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.lineSpacing) {
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.pixel12)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(height: Layout.lineHeight, alignment: .leading)
                        .visualEffect { content, proxy in
                            let frame = proxy.frame(in: .scrollView(axis: .vertical))
                            let progress = max(0, min(1, frame.minY / Layout.fadeDistance))
                            return content
                                .opacity(progress)
                                .scaleEffect(Layout.minScale + (1 - Layout.minScale) * progress, anchor: .top)
                        }
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(height: Layout.visibleHeight)
        .defaultScrollAnchor(.bottom)
        .animation(.easeOut, value: log.count)
    }
}

private enum Layout {
    static let lineCount = 6
    static let lineHeight: CGFloat = 16
    static let lineSpacing: CGFloat = 4
    static let fadeDistance: CGFloat = 18
    static let minScale: CGFloat = 0.96

    static var visibleHeight: CGFloat {
        lineHeight * CGFloat(lineCount) + lineSpacing * CGFloat(lineCount + 1)
    }
}
