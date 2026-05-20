import UIKit

/// Async sprite loader with URL-level caching. Shared across all sprite
/// surfaces (grid, detail, battle, items) via `AppContainer.spriteLoader`.
protocol SpriteLoading: Sendable {
    /// Load a sprite from a remote URL string, returning a cached hit instantly.
    func spriteImage(from urlString: String) async -> UIImage?
}

actor SpriteLoader: SpriteLoading {
    private let session: URLSession
    private let cache: URLCache

    init(session: URLSession = .shared, cache: URLCache = .shared) {
        self.session = session
        self.cache = cache
    }

    func spriteImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        let request = URLRequest(url: url)

        if let cachedResponse = cache.cachedResponse(for: request),
           let sprite = UIImage(data: cachedResponse.data) {
            return sprite
        }

        do {
            let (data, response) = try await session.data(for: request)
            cache.cache(response: response, withData: data, for: request)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

private extension URLCache {
    func cache(response: URLResponse, withData data: Data, for request: URLRequest) {
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            return
        }
        let cached = CachedURLResponse(response: response, data: data)
        storeCachedResponse(cached, for: request)
    }
}
