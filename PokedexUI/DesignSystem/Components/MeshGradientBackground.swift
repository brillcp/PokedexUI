import SwiftUI

/// Animated `MeshGradient` backdrop tinted in shades of `color`.
///
/// Holds five brightness stops (±2) of `color` across a 3×3 mesh. The four
/// edge midpoints slide along their edges and the center wobbles in 2D so
/// the gradient drifts slowly; corners stay pinned so the gradient never
/// bleeds outside its bounds. Intended as a full-bleed background behind
/// detail screens.
struct MeshGradientBackground: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(at: time), colors: shades)
        }
    }
}

// MARK: - Private
private extension MeshGradientBackground {
    func points(at t: TimeInterval) -> [SIMD2<Float>] {
        let amp: Float = 0.16
        let k = 0.64  // global speed multiplier
        let s: (Double, Double) -> Float = { freq, phase in Float(sin(t * freq * k + phase)) }
        let c: (Double, Double) -> Float = { freq, phase in Float(cos(t * freq * k + phase)) }
        return [
            SIMD2(0.00, 0.00),
            SIMD2(0.50 + amp * s(0.7, 0.0), 0.00),
            SIMD2(1.00, 0.00),
            SIMD2(0.00, 0.50 + amp * c(0.6, 1.1)),
            SIMD2(0.50 + amp * s(0.8, 2.0), 0.50 + amp * c(0.9, 0.5)),
            SIMD2(1.00, 0.50 + amp * s(0.5, 3.0)),
            SIMD2(0.00, 1.00),
            SIMD2(0.50 + amp * c(0.7, 1.7), 1.00),
            SIMD2(1.00, 1.00),
        ]
    }

    var shades: [Color] {
        let d = color.shifted(brightness: -0.12)
        let dd  = color.shifted(brightness: -0.24)
        let c  = color
        let l  = color.shifted(brightness: 0.12)
        let ll = color.shifted(brightness:  0.24)
        return [
            dd, d,  c,
            l,  c, d,
            c,  l,  ll,
        ]
    }
}

#Preview {
    MeshGradientBackground(color: Color(hex: "d53b47")!)
        .ignoresSafeArea()
}
