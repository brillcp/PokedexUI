import SwiftUI

/// Scrollable battle log pinned to the latest event, with a fade/shrink
/// effect on the top row so the player can scroll back through history.
///
/// A move tap engages "follow bottom" mode: the feed snaps to the latest
/// row and keeps tracking new events as they arrive during turn
/// animation. The user dragging the feed disengages follow mode, so they
/// can browse history mid-turn without being yanked back.
struct BattleLogFeed: View {
    let log: [AttributedString]
    let scrollToBottomTrigger: Int

    @State private var isFollowingBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Layout.lineSpacing) {
                    ForEach(Array(log.enumerated()), id: \.offset) { offset, line in
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
                            .id(offset)
                    }
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(height: Layout.visibleHeight)
            .defaultScrollAnchor(.bottom)
            .animation(.easeOut, value: log.count)
            .onChange(of: scrollToBottomTrigger) { _, _ in
                isFollowingBottom = true
                snapToBottom(proxy: proxy)
            }
            .onChange(of: log.count) { _, _ in
                if isFollowingBottom { snapToBottom(proxy: proxy) }
            }
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting { isFollowingBottom = false }
            }
        }
    }
}

// MARK: - Private
private extension BattleLogFeed {
    enum Layout {
        static let lineCount = 6
        static let lineHeight: CGFloat = 16
        static let lineSpacing: CGFloat = 4
        static let fadeDistance: CGFloat = 18
        static let minScale: CGFloat = 0.96

        static var visibleHeight: CGFloat {
            lineHeight * CGFloat(lineCount) + lineSpacing * CGFloat(lineCount + 1)
        }
    }

    func snapToBottom(proxy: ScrollViewProxy) {
        guard let last = log.indices.last else { return }
        withAnimation(.easeOut) {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}
