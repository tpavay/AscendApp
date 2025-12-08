//
//  ConsoleScanService.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import UIKit
import FirebaseAuth

/// Service for scanning stair stepper console images via the Cloud Function
actor ConsoleScanService {
    static let shared = ConsoleScanService()

    // MARK: - Configuration

    /// Cloud Function URL - update this after deploying
    /// Format: https://<region>-<project-id>.cloudfunctions.net/consoleScan
    /// Or for v2: https://consolescan-<hash>-uc.a.run.app
    private let functionURL: URL

    /// Maximum image dimension (longest edge) for upload
    private let maxImageDimension: CGFloat = 1200

    /// JPEG compression quality
    private let jpegQuality: CGFloat = 0.7

    // MARK: - Initialization

    init() {
        // TODO: Update this URL after deploying the Cloud Function
        // You can find it in the Firebase Console under Functions
        // Or run: firebase functions:list
        self.functionURL = URL(string: "https://us-central1-ascend-f2e4f.cloudfunctions.net/consoleScan")!
    }

    // MARK: - Public API

    /// Scan a console image and extract workout metrics
    /// - Parameter image: The cropped console image (will be downscaled/compressed)
    /// - Returns: Extracted workout metrics
    func scanConsole(image: UIImage) async throws -> ConsoleScanResult {
        // 1. Get Firebase ID token
        guard let user = Auth.auth().currentUser else {
            throw ConsoleScanError.notAuthenticated
        }

        let idToken: String
        do {
            idToken = try await user.getIDToken()
        } catch {
            throw ConsoleScanError.notAuthenticated
        }

        // 2. Prepare image (downscale + compress)
        guard let imageData = prepareImage(image) else {
            throw ConsoleScanError.unknown("Failed to process image")
        }

        let base64Image = imageData.base64EncodedString()

        // 3. Build request
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["imageBase64": base64Image]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 4. Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConsoleScanError.networkError
        }

        // 5. Handle response
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            return try decoder.decode(ConsoleScanResult.self, from: data)
        } else {
            // Parse error message from response
            let errorMessage: String
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                errorMessage = errorResponse.error
            } else {
                errorMessage = "Unknown error"
            }
            throw ConsoleScanError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    // MARK: - Private Helpers

    /// Downscale and compress image for upload
    private func prepareImage(_ image: UIImage) -> Data? {
        let resized = resizeImage(image, maxDimension: maxImageDimension)
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    /// Resize image so longest edge is at most maxDimension
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let ratio = maxDimension / max(size.width, size.height)

        // Don't upscale
        if ratio >= 1 {
            return image
        }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Helper Types

private struct ErrorResponse: Decodable {
    let error: String
}
