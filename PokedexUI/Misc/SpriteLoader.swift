import UIKit

/// An actor responsible for asynchronously loading and caching sprite images from remote URLs.
///
/// This loader uses `URLSession` for networking and `URLCache` for in-memory/disk caching.
/// Requests are deduplicated through the actor model, and cache hits return instantly.
actor SpriteLoader {
    // MARK: - Private properties
    /// The URL session used for downloading sprite image data.
    private let session: URLSession

    /// The cache used to store sprite image responses.
    private let cache: URLCache

    // MARK: - Initialization
    /// Creates a new sprite loader with optional custom session and cache.
    ///
    /// - Parameters:
    ///   - session: The `URLSession` instance to use. Defaults to `.shared`.
    ///   - cache: The `URLCache` instance to use. Defaults to `.shared`.
    init(session: URLSession = .shared, cache: URLCache = .shared) {
        self.session = session
        self.cache = cache
    }
}

// MARK: - Public functions
extension SpriteLoader {
    /// Loads a sprite from a remote URL string.
    ///
    /// This method checks the cache before making a network request.
    /// If a cached response is found, it returns the sprite immediately.
    ///
    /// - Parameter urlString: The remote sprite URL as a string.
    /// - Returns: A `UIImage` if the sprite was successfully loaded or cached, otherwise `nil`.
    func loadSprite(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        let request = URLRequest(url: url)

        // Return cached image if available
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

// MARK: - Cache helper function
private extension URLCache {
    /// Stores a response in the cache if it is a valid HTTP response (status code 2xx).
    ///
    /// - Parameters:
    ///   - response: The `URLResponse` returned by the server.
    ///   - data: The sprite data to cache.
    ///   - request: The associated `URLRequest` key.
    func cache(response: URLResponse, withData data: Data, for request: URLRequest) {
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            return
        }
        let cached = CachedURLResponse(response: response, data: data)
        storeCachedResponse(cached, for: request)
    }
}
