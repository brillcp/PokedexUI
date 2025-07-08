//
//  ImageLoader.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import UIKit
import Combine

actor ImageLoader {
    static let shared = ImageLoader()

    private let cache = URLCache.shared
    private let session: URLSession = .shared

    func loadImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        let request = URLRequest(url: url)

        // Return cached image if available
        if let cachedResponse = cache.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            return image
        }

        do {
            let (data, response) = try await session.data(for: request)

            // Cache if valid HTTP response
            if let httpResponse = response as? HTTPURLResponse,
               200..<300 ~= httpResponse.statusCode {
                let cachedData = CachedURLResponse(response: response, data: data)
                cache.storeCachedResponse(cachedData, for: request)
            }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

/*
final class ImageLoader: ObservableObject {
    
    // MARK: Private properties
    private var cancellable: AnyCancellable?
    private let url: URL
    
    // MARK: - Public properties
    @Published var image: UIImage?

    // MARK: - Init
    init(url: URL) {
        self.url = url
    }
    
    deinit {
        cancel()
    }
    
    // MARK: - Public functions
    func load() {
        cancellable = URLSession.shared.dataTaskPublisher(for: url)
            .map { UIImage(data: $0.data) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.image = $0 }
    }
    
    func cancel() {
        cancellable?.cancel()
    }
}
*/
