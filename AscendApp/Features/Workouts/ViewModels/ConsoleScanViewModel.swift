//
//  ConsoleScanViewModel.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI
import PhotosUI

/// View model for the console scanning flow
@MainActor
@Observable
class ConsoleScanViewModel {
    // MARK: - State

    enum ScanState: Equatable {
        case selectingSource
        case cropping(UIImage)
        case processing
        case confirmation(ConsoleScanResult, UIImage)
        case error(String)

        static func == (lhs: ScanState, rhs: ScanState) -> Bool {
            switch (lhs, rhs) {
            case (.selectingSource, .selectingSource):
                return true
            case (.cropping, .cropping):
                return true
            case (.processing, .processing):
                return true
            case (.confirmation, .confirmation):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    var state: ScanState = .selectingSource

    // For PhotosPicker
    var selectedPhotoItem: PhotosPickerItem?

    // Camera state
    var showingCamera = false
    var capturedImage: UIImage?

    // MARK: - Dependencies

    private let scanService = ConsoleScanService.shared
    private let hapticsManager = HapticsManager.shared

    // MARK: - Actions

    /// Handle image selected from photo library
    func handlePhotoSelection() async {
        guard let item = selectedPhotoItem else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                state = .cropping(image)
            }
        } catch {
            state = .error("Failed to load image")
        }
    }

    /// Handle image captured from camera
    func handleCameraCapture(_ image: UIImage) {
        showingCamera = false
        state = .cropping(image)
    }

    /// Process the cropped image
    func processCroppedImage(_ croppedImage: UIImage) async {
        state = .processing
        hapticsManager.trigger(.mediumImpact)

        do {
            let result = try await scanService.scanConsole(image: croppedImage)
            hapticsManager.trigger(.success)
            state = .confirmation(result, croppedImage)
        } catch let error as ConsoleScanError {
            hapticsManager.trigger(.error)
            state = .error(error.localizedDescription)
        } catch {
            hapticsManager.trigger(.error)
            state = .error("An unexpected error occurred")
        }
    }

    /// Go back to source selection
    func rescan() {
        selectedPhotoItem = nil
        capturedImage = nil
        state = .selectingSource
    }

    /// Reset to initial state
    func reset() {
        selectedPhotoItem = nil
        capturedImage = nil
        showingCamera = false
        state = .selectingSource
    }
}
