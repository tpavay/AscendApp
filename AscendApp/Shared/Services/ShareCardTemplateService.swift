//
//  ShareCardTemplateService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/19/25.
//

import Foundation
import UIKit
import ImageIO
@preconcurrency import FirebaseFirestore
import FirebaseStorage

/// Service for fetching and caching remote share card templates
final class ShareCardTemplateService: @unchecked Sendable {
    static let shared = ShareCardTemplateService()

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    /// Target size for downsampling (matches share export size)
    private let targetSize = CGSize(width: 1080, height: 1350)

    /// Session guard to avoid redundant preloads
    private var hasPreloadedThisSession = false

    /// Currently loaded templates (after filtering and sorting)
    private(set) var loadedTemplates: [ShareCardTemplate] = []

    /// Track which template images are loaded
    private(set) var loadedTemplateImages: [String: UIImage] = [:]

    /// Loading state
    private(set) var isLoading = false

    private init() {}

    // MARK: - Public API

    /// Preload templates if not already done this session
    /// Call this from workout detail view to anticipate sharing
    func preloadIfNeeded(userGender: Gender? = nil) {
        guard !hasPreloadedThisSession else {
            print("📸 ShareCardTemplateService: Already preloaded this session, skipping")
            return
        }
        hasPreloadedThisSession = true
        print("📸 ShareCardTemplateService: preloadIfNeeded called, starting preload...")

        Task(priority: .utility) {
            await loadTemplates(userGender: userGender)
        }
    }

    /// Force reload templates (e.g., after user changes gender)
    func reload(userGender: Gender? = nil) async {
        hasPreloadedThisSession = false
        await loadTemplates(userGender: userGender)
    }

    /// Get cached image for a template
    func image(for templateId: String) -> UIImage? {
        loadedTemplateImages[templateId]
    }

    // MARK: - Private Implementation

    private func loadTemplates(userGender: Gender?) async {
        guard !isLoading else {
            print("📸 ShareCardTemplateService: Already loading, skipping")
            return
        }
        isLoading = true
        print("📸 ShareCardTemplateService: Starting to load templates...")

        defer { isLoading = false }

        do {
            // 1. Fetch manifest from Firestore
            print("📸 ShareCardTemplateService: Fetching config from Firestore...")
            let config = try await fetchTemplatesConfig()
            print("📸 ShareCardTemplateService: Found \(config.templates.count) templates in config")

            // 2. Filter by gender
            let filtered = filterTemplates(config.templates, for: userGender)
            print("📸 ShareCardTemplateService: After filtering: \(filtered.count) templates")

            // 3. Sort with stable ordering
            let sorted = sortTemplates(filtered)

            // 4. Download and cache images
            print("📸 ShareCardTemplateService: Downloading images...")
            await downloadAndCacheImages(for: sorted)
            print("📸 ShareCardTemplateService: Downloaded \(loadedTemplateImages.count) images")

            // 5. Store loaded templates
            await MainActor.run {
                self.loadedTemplates = sorted
                print("📸 ShareCardTemplateService: Loaded \(self.loadedTemplates.count) templates successfully")
            }
        } catch {
            print("📸 ShareCardTemplateService: Failed to load templates - \(error)")
            TelemetryManager.shared.recordError(
                error,
                context: .firestore,
                code: "share_card_templates_fetch_failed"
            )
        }
    }

    private func fetchTemplatesConfig() async throws -> ShareCardTemplatesConfig {
        let document = try await db.collection("config").document("shareCardTemplates").getDocument()

        print("📸 ShareCardTemplateService: Document exists: \(document.exists)")

        guard let data = document.data() else {
            print("📸 ShareCardTemplateService: No data in document!")
            throw ShareCardTemplateError.noData
        }

        print("📸 ShareCardTemplateService: Document data keys: \(data.keys)")
        print("📸 ShareCardTemplateService: Raw data: \(data)")

        // Decode templates array
        guard let templatesData = data["templates"] as? [[String: Any]] else {
            print("📸 ShareCardTemplateService: 'templates' field not found or wrong type")
            print("📸 ShareCardTemplateService: templates raw value: \(String(describing: data["templates"]))")
            throw ShareCardTemplateError.invalidFormat
        }

        print("📸 ShareCardTemplateService: Found \(templatesData.count) raw template entries")

        let version = data["version"] as? Int ?? 1

        let templates: [ShareCardTemplate] = templatesData.compactMap { dict in
            // Debug: print exact types
            print("📸 Types - id: \(type(of: dict["id"])), storagePath: \(type(of: dict["storagePath"])), sortOrder: \(type(of: dict["sortOrder"]))")

            // Try multiple ways to get the values
            let id: String?
            if let s = dict["id"] as? String {
                id = s
            } else if let ns = dict["id"] {
                id = "\(ns)"
            } else {
                id = nil
            }

            let storagePath: String?
            if let s = dict["storagePath"] as? String {
                storagePath = s
            } else if let ns = dict["storagePath"] {
                storagePath = "\(ns)"
            } else {
                storagePath = nil
            }

            let sortOrder: Int
            if let n = dict["sortOrder"] as? Int {
                sortOrder = n
            } else if let n = dict["sortOrder"] as? Int64 {
                sortOrder = Int(n)
            } else if let n = dict["sortOrder"] as? NSNumber {
                sortOrder = n.intValue
            } else if let n = dict["sortOrder"] {
                sortOrder = Int("\(n)") ?? 0
            } else {
                print("📸 ShareCardTemplateService: Failed to parse sortOrder")
                return nil
            }

            guard let finalId = id, let finalPath = storagePath else {
                print("📸 ShareCardTemplateService: Failed - id: \(id ?? "nil"), path: \(storagePath ?? "nil")")
                return nil
            }

            let genderValue = dict["gender"]
            let genderString: String? = genderValue as? String ?? (genderValue != nil ? "\(genderValue!)" : nil)
            let gender = genderString.flatMap { Gender(rawValue: $0) }

            print("📸 ShareCardTemplateService: Successfully parsed template: \(finalId)")

            return ShareCardTemplate(
                id: finalId,
                storagePath: finalPath,
                gender: gender,
                sortOrder: sortOrder
            )
        }

        return ShareCardTemplatesConfig(templates: templates, version: version)
    }

    /// Filter templates based on user's gender
    /// - nil/unspecified user gender: return all templates
    /// - male: return templates where gender == nil OR male
    /// - female: return templates where gender == nil OR female
    private func filterTemplates(_ templates: [ShareCardTemplate], for userGender: Gender?) -> [ShareCardTemplate] {
        guard let userGender = userGender else {
            // No gender set - return all templates
            return templates
        }

        return templates.filter { template in
            // Include if template is universal (nil) or matches user gender
            template.gender == nil || template.gender == userGender
        }
    }

    /// Sort templates with stable ordering
    /// Primary: sortOrder ascending
    /// Tie-breaker: id ascending
    private func sortTemplates(_ templates: [ShareCardTemplate]) -> [ShareCardTemplate] {
        templates.sorted { a, b in
            if a.sortOrder != b.sortOrder {
                return a.sortOrder < b.sortOrder
            }
            return a.id < b.id
        }
    }

    private func downloadAndCacheImages(for templates: [ShareCardTemplate]) async {
        print("📸 ShareCardTemplateService: Starting to download \(templates.count) images")

        for template in templates {
            print("📸 ShareCardTemplateService: Downloading image for \(template.id)...")

            // Skip if already in ImageCache
            let cacheKey = URL(string: "share-card-template://\(template.id)")!
            if ImageCache.shared.image(for: cacheKey) != nil {
                print("📸 ShareCardTemplateService: \(template.id) already cached, skipping")
                continue
            }

            let image = await downloadAndDecodeImage(for: template)

            if let image = image {
                print("📸 ShareCardTemplateService: Successfully downloaded \(template.id)")
                ImageCache.shared.store(image, for: cacheKey)
                loadedTemplateImages[template.id] = image
            } else {
                print("📸 ShareCardTemplateService: Failed to download \(template.id)")
            }
        }

        print("📸 ShareCardTemplateService: Finished downloading, got \(loadedTemplateImages.count) images")
    }

    private func downloadAndDecodeImage(for template: ShareCardTemplate) async -> UIImage? {
        do {
            // 1. Get download URL from storage path
            print("📸 ShareCardTemplateService: Getting download URL for \(template.storagePath)")
            let storageRef = storage.reference(withPath: template.storagePath)
            let downloadURL = try await storageRef.downloadURL()
            print("📸 ShareCardTemplateService: Got URL: \(downloadURL)")

            // 2. Download image data
            print("📸 ShareCardTemplateService: Downloading data...")
            let (data, _) = try await URLSession.shared.data(from: downloadURL)
            print("📸 ShareCardTemplateService: Downloaded \(data.count) bytes")

            // 3. Decode and downsample off-main-thread
            let image = downsampleImage(data: data, to: targetSize)
            print("📸 ShareCardTemplateService: Decoded image: \(image != nil ? "success" : "failed")")
            return image
        } catch {
            print("📸 ShareCardTemplateService: Failed to download image for \(template.id) - \(error)")
            return nil
        }
    }

    /// Efficiently downsample image using CGImageSource
    /// This decodes directly at the target size, avoiding memory spikes
    private func downsampleImage(data: Data, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }

        // Calculate max dimension for downsampling
        let maxDimension = max(targetSize.width, targetSize.height)

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }
}

// MARK: - Errors

enum ShareCardTemplateError: Error {
    case noData
    case invalidFormat
}
