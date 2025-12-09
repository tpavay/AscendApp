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
        case confirmation(ConsoleScanResult, UIImage)
        case error(String)

        static func == (lhs: ScanState, rhs: ScanState) -> Bool {
            switch (lhs, rhs) {
            case (.selectingSource, .selectingSource):
                return true
            case (.cropping, .cropping):
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

    // Processing state (shown as overlay, not separate view)
    var isProcessing = false
    private var currentScanTask: Task<Void, Never>?

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
    func processCroppedImage(_ croppedImage: UIImage) {
        isProcessing = true
        hapticsManager.trigger(.mediumImpact)

        currentScanTask = Task {
            do {
                let result = try await scanService.scanConsole(image: croppedImage)

                // Check if cancelled before updating state
                guard !Task.isCancelled else { return }

                hapticsManager.trigger(.success)
                isProcessing = false
                state = .confirmation(result, croppedImage)
            } catch let error as ConsoleScanError {
                guard !Task.isCancelled else { return }
                hapticsManager.trigger(.error)
                isProcessing = false
                state = .error(error.localizedDescription)
            } catch {
                guard !Task.isCancelled else { return }
                hapticsManager.trigger(.error)
                isProcessing = false
                state = .error("An unexpected error occurred")
            }
        }
    }

    /// Cancel the current scanning operation
    func cancelScanning() {
        currentScanTask?.cancel()
        currentScanTask = nil
        isProcessing = false
        // Stay on current view (don't change state)
    }

    /// Go back to source selection
    func rescan() {
        selectedPhotoItem = nil
        capturedImage = nil
        state = .selectingSource
    }

    /// Reset to initial state
    func reset() {
        currentScanTask?.cancel()
        currentScanTask = nil
        isProcessing = false
        selectedPhotoItem = nil
        capturedImage = nil
        showingCamera = false
        state = .selectingSource
    }
}
