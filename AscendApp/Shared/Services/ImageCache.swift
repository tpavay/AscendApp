//
//  ImageCache.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/19/25.
//

import UIKit

/// In-memory image cache using NSCache
/// - Thread-safe for concurrent access (NSCache is thread-safe)
/// - Automatically evicts images under memory pressure
/// - Zero disk footprint
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        // Limit to ~50 images in memory
        cache.countLimit = 50
        // Limit total memory to ~100MB (rough estimate based on cost)
        cache.totalCostLimit = 100 * 1024 * 1024
    }

    /// Retrieve a cached image for the given URL
    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Store an image in the cache
    /// - Parameters:
    ///   - image: The image to cache
    ///   - url: The URL key to associate with the image
    func store(_ image: UIImage, for url: URL) {
        // Estimate cost based on image size in bytes
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Remove a specific image from the cache
    func remove(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    /// Clear all cached images
    func clearAll() {
        cache.removeAllObjects()
    }
}
