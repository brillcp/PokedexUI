import UIKit

/// An actor responsible for asynchronously loading and caching images from remote URLs.
///
/// This loader uses `URLSession` for networking and `URLCache` for in-memory/disk caching.
/// Requests are deduplicated through the actor model, and cache hits return instantly.
actor ImageLoader {
    // MARK: - Private properties

    /// The URL session used for downloading image data.
    private let session: URLSession

    /// The cache used to store image responses.
    private let cache: URLCache

    // MARK: - Initialization
    /// Creates a new image loader with optional custom session and cache.
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
extension ImageLoader {
    /// Loads an image from a remote URL string.
    ///
    /// This method checks the cache before making a network request.
    /// If a cached response is found, it returns the image immediately.
    ///
    /// - Parameter urlString: The remote image URL as a string.
    /// - Returns: A `UIImage` if the image was successfully loaded or cached, otherwise `nil`.
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
    ///   - data: The image data to cache.
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
