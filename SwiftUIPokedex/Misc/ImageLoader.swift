import UIKit

actor ImageLoader {
    static let shared = ImageLoader()

    private let cache = URLCache.shared
    private let session: URLSession = .shared

    func loadImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        let request = URLRequest(url: url)

        // Return cached image if available
        if let cachedResponse = cache.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            return image
        }

        do {
            let (data, response) = try await session.data(for: request)
            cache.cache(
                response: response,
                withData: data,
                for: request
            )
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Cache helper function
private extension URLCache {
    func cache(response: URLResponse, withData data: Data, for request: URLRequest) {
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode
        else { return }
        let cachedData = CachedURLResponse(response: response, data: data)
        storeCachedResponse(cachedData, for: request)
    }
}
