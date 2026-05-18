import SwiftUI

/// Custom activity indicator that mirrors the layout of `UIActivityIndicator`
/// (a ring of fading spokes rotating clockwise in discrete steps) but uses
/// sharp-cornered rectangular ticks instead of the system's rounded capsules.
/// Matches the pixel-font / gameboy aesthetic used elsewhere in the design
/// system; capsule spokes look too modern beside `RoundedRectangle.chip`.
///
/// Steps the front-most spoke through `lineCount` positions per second so the
/// motion has the same staccato feel as the system spinner. Driven by
/// `TimelineView`, so no `@State` and no `onAppear` plumbing; the view is
/// stateless and re-renders only when the timeline fires.
struct PixelSpinner: View {
    let size: CGFloat
    let color: Color
    let lineCount: Int
    let lineWidth: CGFloat
    let lineLength: CGFloat

    init(
        size: CGFloat = 28,
        color: Color = .secondary,
        lineCount: Int = 8,
        lineWidth: CGFloat = 2.5,
        lineLength: CGFloat = 8
    ) {
        self.size = size
        self.color = color
        self.lineCount = lineCount
        self.lineWidth = lineWidth
        self.lineLength = lineLength
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / Double(lineCount))) { context in
            let step = currentStep(at: context.date)
            spokeRing
                .rotationEffect(.degrees(Double(step) * stepAngle))
                .frame(width: size, height: size)
        }
        .accessibilityLabel("Loading")
    }
}

// MARK: - Subviews + math

private extension PixelSpinner {
    var spokeRing: some View {
        ZStack {
            ForEach(0..<lineCount, id: \.self) { index in
                Rectangle()
                    .fill(color)
                    .frame(width: lineWidth, height: lineLength)
                    .offset(y: -(size / 2 - lineLength / 2))
                    .rotationEffect(.degrees(Double(index) * stepAngle))
                    .opacity(Double(index + 1) / Double(lineCount))
            }
        }
    }

    var stepAngle: Double { 360.0 / Double(lineCount) }

    /// Maps the timeline date onto a discrete spoke index. Using the absolute
    /// reference-date timestamp keeps every spinner in the app phase-locked,
    /// so multiple instances on screen tick in unison.
    func currentStep(at date: Date) -> Int {
        let seconds = date.timeIntervalSinceReferenceDate
        return Int(seconds * Double(lineCount)) % lineCount
    }
}

#Preview {
    VStack(spacing: 32) {
        PixelSpinner()
        PixelSpinner(size: 48, color: .yellow, lineWidth: 3, lineLength: 12)
        PixelSpinner(size: 64, color: .white, lineCount: 16, lineWidth: 2, lineLength: 14)
    }
    .padding()
    .background(Color.black)
}
