import SwiftUI

/// Horizontal sine-wave shake driven by a monotonically increasing tick.
/// Increment the tick once per damage event; SwiftUI animates the transition,
/// producing a quick wobble that returns to rest.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
