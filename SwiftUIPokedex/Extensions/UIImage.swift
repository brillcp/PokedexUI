import UIKit

private struct RGB: Hashable {
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

// MARK: -
extension UIImage {
    var dominantColor: UIColor? {
        guard let cgImage = resize(to: CGSize(width: 50, height: 50))?.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        var colorCounts: [RGB: Int] = [:]

        for x in 0..<width {
            for y in 0..<height {
                let pixelIndex = ((width * y) + x) * 4
                let alpha = bytes[pixelIndex + 3]
                guard alpha >= 127 else { continue }

                let color = RGB(
                    r: bytes[pixelIndex + 2], // R
                    g: bytes[pixelIndex + 1], // G
                    b: bytes[pixelIndex + 0]  // B
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
                if Double(count) / Double(colorCounts[dominant] ?? 1) > 0.3, !candidate.isBlackOrWhite {
                    dominant = candidate
                    break
                }
            }
        }

        return dominant.toUIColor()
    }

    private func resize(to targetSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: targetSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
