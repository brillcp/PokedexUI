import UIKit

actor ImageLoader {
    // MARK: Private properties
    private let session: URLSession
    private let cache: URLCache

    // MARK: - Init
    init(session: URLSession = .shared, cache: URLCache = .shared) {
        self.session = session
        self.cache = cache
    }
}

// MARK: - Public functions
extension ImageLoader {
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
        storeCachedResponse(.init(response: response, data: data), for: request)
    }
}
