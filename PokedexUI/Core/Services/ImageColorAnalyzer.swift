import SwiftUI

/// Extracts and caches dominant sprite colors via downsampled pixel scanning.
/// Shared via `AppContainer.imageColorAnalyzer`.
protocol ImageColorAnalyzing: Sendable {
    /// Extract the dominant non-black/white color for a pokemon sprite.
    func dominantColor(for id: Int, image: UIImage) async -> Color?
}

actor ImageColorAnalyzer: ImageColorAnalyzing {
    private var cache = [Int: Color]()

    func dominantColor(for id: Int, image: UIImage) -> Color? {
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

        if dominant.isBlackOrWhite,
           let fallback = sortedColors.first(where: { !$0.key.isBlackOrWhite })?.key {
            dominant = fallback
        }

        let final = dominant.toColor()
        cache[id] = final
        return final
    }
}

private extension ImageColorAnalyzer {
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

        func toColor() -> Color {
            Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}
