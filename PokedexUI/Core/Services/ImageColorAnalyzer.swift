import UIKit

/// Extracts the dominant color from a sprite via a downsampled 50x50 pixel
/// scan. Caches results per pokemon id so repeat lookups in the same session
/// skip the pixel work. Off-main by being an actor; the scan is CPU-only and
/// short (a few ms per sprite) so it doesn't need any further parallelisation.
actor ImageColorAnalyzer {
    private var cache = [Int: UIColor]()
}

// MARK: - Public functions
extension ImageColorAnalyzer {
    func dominantColor(for id: Int, image: UIImage) -> UIColor? {
        if let cached = cache[id] { return cached }

        guard let cgImage = image.resize(to: CGSize(width: 50, height: 50))?.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        var colorCounts: [RGB: Int] = [:]

        for x in 0..<width {
            for y in 0..<height {
                let index = ((width * y) + x) * 4
                let alpha = bytes[index + 3]
                guard alpha >= 127 else { continue }

                let color = RGB(
                    r: bytes[index + 2],
                    g: bytes[index + 1],
                    b: bytes[index + 0]
                )
                colorCounts[color, default: 0] += 1
            }
        }

        let threshold = Int(CGFloat(height) * 0.01)
        let sortedColors = colorCounts
            .filter { $0.value > threshold }
            .sorted { $0.value > $1.value }

        guard var dominant = sortedColors.first?.key else { return nil }

        if dominant.isBlackOrWhite {
            for (candidate, count) in sortedColors.dropFirst() {
                if Double(count) / Double(colorCounts[dominant] ?? 1) > 0.3,
                   !candidate.isBlackOrWhite {
                    dominant = candidate
                    break
                }
            }
        }

        let final = dominant.toUIColor()
        cache[id] = final
        return final
    }
}

// MARK: - Private properties
private extension ImageColorAnalyzer {
    /// Compact RGB triple for histogram counting. Kept private because the
    /// outer actor's only output is a `UIColor`; this is an implementation
    /// detail of the scan.
    struct RGB: Hashable {
        let r: UInt8
        let g: UInt8
        let b: UInt8

        var isBlackOrWhite: Bool {
            (r > 232 && g > 232 && b > 232) || (r < 23 && g < 23 && b < 23)
        }

        var isDark: Bool {
            let luminance = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            return luminance < 127.5
        }

        func toUIColor() -> UIColor {
            UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }
}
