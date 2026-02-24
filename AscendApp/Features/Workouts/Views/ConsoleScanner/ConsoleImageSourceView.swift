//
//  ConsoleImageSourceView.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

/// View with live camera preview and crop frame overlay for scanning console
struct ConsoleImageSourceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var themeManager = ThemeManager.shared
    @Bindable var viewModel: ConsoleScanViewModel

    // Camera state
    @State private var cameraManager = CameraManager()
    @State private var cameraAccessState: CameraAuthorizationState = .notDetermined
    @State private var isPresentingPhotoPicker = false
    @State private var capturedPreviewImage: UIImage?

    // Crop box aspect ratio (16:9 for most console displays)
    private let cropAspectRatio: CGFloat = 16.0 / 9.0

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        GeometryReader { geometry in
            let cropBoxSize = calculateCropBoxSize(in: geometry.size)

            ZStack {
                // Black background
                Color.black.ignoresSafeArea()

                // Show captured image when processing, otherwise show live camera preview
                if let capturedImage = capturedPreviewImage {
                    // Frozen captured image while processing
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cropBoxSize.width, height: cropBoxSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Live camera preview clipped to crop box
                    CameraPreviewView(
                        cameraManager: cameraManager,
                        layerVersion: cameraManager.previewLayerVersion
                    )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 8)
                                .size(width: cropBoxSize.width, height: cropBoxSize.height)
                                .offset(
                                    x: (geometry.size.width - cropBoxSize.width) / 2,
                                    y: (geometry.size.height - cropBoxSize.height) / 2
                                )
                        )
                }

                // Crop box border
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: cropBoxSize.width, height: cropBoxSize.height)

                // Instructions and buttons
                VStack {
                    // Top instruction
                    Text("Capture your stair stepper stats in the frame")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.top, 60)

                    Spacer()

                    // Bottom buttons
                    VStack(spacing: 16) {
                        // Take Photo / Enable Camera button
                        Button {
                            handleTakePhotoTap(cropBoxSize: cropBoxSize, containerSize: geometry.size)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: takePhotoButtonIcon)
                                    .font(.system(size: 20))
                                Text(takePhotoButtonTitle)
                                    .font(.montserratSemiBold(size: 16))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(viewModel.isProcessing)

                        // Choose from Library button
                        Button {
                            handlePhotoPickerTap()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 20))
                                Text("Choose from Library")
                                    .font(.montserratSemiBold(size: 16))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .photosPicker(
                            isPresented: $isPresentingPhotoPicker,
                            selection: $viewModel.selectedPhotoItem,
                            matching: .images
                        )
                        .disabled(viewModel.isProcessing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }

                // Processing overlay
                if viewModel.isProcessing {
                    ProcessingOverlay()
                }
            }
        }
        .onAppear {
            // Clear any previously captured image (e.g., after rescan)
            capturedPreviewImage = nil

            // Check current status without requesting - this enables preview if already authorized
            let status = cameraManager.currentAuthorizationState()
            cameraAccessState = status
            if status == .authorized {
                Task { await cameraManager.requestPermissionAndSetup() }
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            // Re-check status when returning from Settings
            let status = cameraManager.currentAuthorizationState()
            cameraAccessState = status
            if status == .authorized && !cameraManager.isSessionRunning {
                Task { await cameraManager.requestPermissionAndSetup() }
            }
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, _ in
            Task {
                await viewModel.handlePhotoSelection()
            }
        }
    }

    /// Calculate crop box size to fit container while maintaining aspect ratio
    private func calculateCropBoxSize(in containerSize: CGSize) -> CGSize {
        let maxWidth = containerSize.width - 40 // 20pt padding on each side
        let maxHeight = containerSize.height * 0.5 // Max 50% of height

        let widthBasedHeight = maxWidth / cropAspectRatio
        let heightBasedWidth = maxHeight * cropAspectRatio

        if widthBasedHeight <= maxHeight {
            return CGSize(width: maxWidth, height: widthBasedHeight)
        } else {
            return CGSize(width: heightBasedWidth, height: maxHeight)
        }
    }

    /// Capture burst of photos and crop the best one to frame bounds
    /// Uses burst capture to handle digital display refresh rates
    private func capturePhoto(cropBoxSize: CGSize, containerSize: CGSize) {
        guard cameraManager.canCapture else {
            // Camera not ready yet
            return
        }

        viewModel.isProcessing = true

        cameraManager.captureBurst { images in
            guard !images.isEmpty else {
                viewModel.isProcessing = false
                return
            }

            // Select the best image from the burst
            // For digital displays, we want the sharpest image with most visible content
            let bestImage = selectBestImage(from: images)

            // Crop the captured image to the frame area
            if let croppedImage = cropImageToFrame(
                image: bestImage,
                cropBoxSize: cropBoxSize,
                containerSize: containerSize
            ) {
                // Show the captured image while processing
                capturedPreviewImage = croppedImage
                // Skip crop view, go straight to processing
                viewModel.processCroppedImage(croppedImage)
            } else {
                // Fallback: use full image and go to crop view
                capturedPreviewImage = bestImage
                viewModel.handleCameraCapture(bestImage)
            }
        }
    }

    /// Select the best image from a burst for digital display scanning
    /// Prioritizes images with higher contrast/sharpness
    private func selectBestImage(from images: [UIImage]) -> UIImage {
        guard images.count > 1 else { return images.first! }

        // Score each image based on brightness variance (indicates visible content)
        var bestImage = images.first!
        var bestScore: CGFloat = 0

        for image in images {
            let score = calculateImageScore(image)
            if score > bestScore {
                bestScore = score
                bestImage = image
            }
        }

        return bestImage
    }

    /// Calculate a quality score for an image based on brightness variance
    /// Higher variance typically means more visible content on digital displays
    private func calculateImageScore(_ image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0 }

        // Sample the center portion of the image (where console display would be)
        let width = cgImage.width
        let height = cgImage.height
        let sampleSize = min(width, height) / 4
        let centerX = (width - sampleSize) / 2
        let centerY = (height - sampleSize) / 2

        guard let croppedCGImage = cgImage.cropping(to: CGRect(
            x: centerX, y: centerY,
            width: sampleSize, height: sampleSize
        )) else { return 0 }

        // Create a small bitmap to analyze
        let bitmapSize = 50
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: bitmapSize * bitmapSize)

        guard let context = CGContext(
            data: &pixels,
            width: bitmapSize,
            height: bitmapSize,
            bitsPerComponent: 8,
            bytesPerRow: bitmapSize,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: bitmapSize, height: bitmapSize))

        // Calculate variance in brightness
        let mean = CGFloat(pixels.reduce(0) { $0 + Int($1) }) / CGFloat(pixels.count)
        let variance = pixels.reduce(0.0) { sum, pixel in
            let diff = CGFloat(pixel) - mean
            return sum + diff * diff
        } / CGFloat(pixels.count)

        return variance
    }

    /// Crop the captured image to match the visible frame area
    private func cropImageToFrame(
        image: UIImage,
        cropBoxSize: CGSize,
        containerSize: CGSize
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // The camera preview fills the container, so we need to calculate
        // what portion of the image corresponds to the crop box

        // Calculate the aspect ratios
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        var visibleImageRect: CGRect

        if imageAspect > containerAspect {
            // Image is wider - height fills container, width is cropped
            let visibleWidth = imageSize.height * containerAspect
            let xOffset = (imageSize.width - visibleWidth) / 2
            visibleImageRect = CGRect(x: xOffset, y: 0, width: visibleWidth, height: imageSize.height)
        } else {
            // Image is taller - width fills container, height is cropped
            let visibleHeight = imageSize.width / containerAspect
            let yOffset = (imageSize.height - visibleHeight) / 2
            visibleImageRect = CGRect(x: 0, y: yOffset, width: imageSize.width, height: visibleHeight)
        }

        // Calculate crop box position as a fraction of the container
        let cropBoxFractionX = (containerSize.width - cropBoxSize.width) / 2 / containerSize.width
        let cropBoxFractionY = (containerSize.height - cropBoxSize.height) / 2 / containerSize.height
        let cropBoxFractionWidth = cropBoxSize.width / containerSize.width
        let cropBoxFractionHeight = cropBoxSize.height / containerSize.height

        // Apply these fractions to the visible image rect
        let cropRect = CGRect(
            x: visibleImageRect.minX + cropBoxFractionX * visibleImageRect.width,
            y: visibleImageRect.minY + cropBoxFractionY * visibleImageRect.height,
            width: cropBoxFractionWidth * visibleImageRect.width,
            height: cropBoxFractionHeight * visibleImageRect.height
        )

        // Ensure crop rect is within image bounds
        let clampedRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))

        guard clampedRect.width > 100 && clampedRect.height > 100,
              let croppedCGImage = cgImage.cropping(to: clampedRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Camera permission handling

    private var takePhotoButtonTitle: String {
        switch cameraAccessState {
        case .denied, .restricted:
            return "Enable Camera"
        default:
            return "Take Photo"
        }
    }

    private var takePhotoButtonIcon: String {
        switch cameraAccessState {
        case .denied, .restricted:
            return "camera.badge.ellipsis"
        default:
            return "camera.fill"
        }
    }

    private func handleTakePhotoTap(cropBoxSize: CGSize, containerSize: CGSize) {
        switch cameraAccessState {
        case .authorized:
            // Camera ready - capture photo
            capturePhoto(cropBoxSize: cropBoxSize, containerSize: containerSize)

        case .notDetermined:
            // First time - request permission, then show preview (don't auto-capture)
            Task {
                let status = await cameraManager.requestPermissionAndSetup()
                cameraAccessState = status
                // If denied, button will update to show "Enable Camera"
                // If authorized, camera preview will now be visible for user to frame their shot
            }

        case .denied, .restricted:
            // Permission denied - open Settings
            openSettings()

        case .unavailable:
            // No camera available - do nothing (user can use photo library)
            break
        }
    }

    private func handlePhotoPickerTap() {
        isPresentingPhotoPicker = true
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Camera permission types

enum CameraAuthorizationState {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unavailable
}

// MARK: - Processing Overlay

struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            // Darkened background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            // Content
            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                VStack(spacing: 8) {
                    Text("Analyzing console image...")
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(.white)

                    Text("This may take a few seconds")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Camera Manager

/// Wraps a non-Sendable value for safe transfer across concurrency domains
/// when the caller guarantees exclusive access during the transfer.
private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

@MainActor
@Observable
class CameraManager: NSObject {
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var captureCompletion: (([UIImage]) -> Void)?

    // Burst capture settings for digital displays
    private var burstImages: [UIImage] = []
    private var burstCount = 0
    private var targetBurstCount = 5 // Capture 5 frames to handle refresh rate issues

    var isSessionRunning = false
    var previewLayer: AVCaptureVideoPreviewLayer?

    // This triggers SwiftUI updates when preview layer changes
    var previewLayerVersion = 0
    var canCapture: Bool {
        photoOutput != nil && isSessionRunning
    }

    func currentAuthorizationState() -> CameraAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    func requestPermissionAndSetup() async -> CameraAuthorizationState {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            let setupResult = await setupSession()
            return setupResult ? .authorized : .unavailable
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                let setupResult = await setupSession()
                return setupResult ? .authorized : .unavailable
            } else {
                return .denied
            }
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    private func setupSession() async -> Bool {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return false
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            photoOutput = output
        }

        captureSession = session

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        previewLayerVersion += 1 // Trigger SwiftUI update

        // Start session on background thread and wait for result
        let sessionBox = UncheckedBox(session)
        let isRunning: Bool = await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                sessionBox.value.startRunning()
                continuation.resume(returning: sessionBox.value.isRunning)
            }
        }
        isSessionRunning = isRunning

        return isSessionRunning
    }

    func stopSession() {
        guard let session = captureSession else { return }
        isSessionRunning = false // Optimistic update on @MainActor
        let sessionBox = UncheckedBox(session)
        Task.detached(priority: .userInitiated) {
            sessionBox.value.stopRunning()
        }
    }

    /// Capture a burst of photos to handle digital display refresh rates
    /// Digital displays refresh at varying rates, so a single photo may capture
    /// the display mid-refresh with missing segments. Burst capture gives us
    /// multiple frames to choose from.
    func captureBurst(completion: @escaping ([UIImage]) -> Void) {
        guard let photoOutput = photoOutput else {
            completion([])
            return
        }

        burstImages = []
        burstCount = 0
        captureCompletion = completion

        // Capture multiple frames in rapid succession
        captureNextBurstFrame(photoOutput: photoOutput)
    }

    private func captureNextBurstFrame(photoOutput: AVCapturePhotoOutput) {
        guard burstCount < targetBurstCount else {
            // All burst frames captured, return results
            let images = burstImages
            burstImages = []
            captureCompletion?(images)
            captureCompletion = nil
            return
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off // LED displays are self-lit
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Extract data on the callback thread before switching to MainActor
        let imageData: Data?
        if error == nil {
            imageData = photo.fileDataRepresentation()
        } else {
            imageData = nil
        }

        Task { @MainActor in
            if let data = imageData,
               let image = UIImage(data: data) {
                burstImages.append(image)
            }

            burstCount += 1

            // Small delay between burst captures to catch different refresh phases
            if burstCount < targetBurstCount {
                try? await Task.sleep(for: .milliseconds(50))
                if let photoOutput = photoOutput {
                    captureNextBurstFrame(photoOutput: photoOutput)
                }
            } else {
                // All frames captured
                let images = burstImages
                burstImages = []
                captureCompletion?(images)
                captureCompletion = nil
            }
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager
    // Observe version changes to trigger updateUIView when layer becomes available
    let layerVersion: Int

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.setPreviewLayer(cameraManager.previewLayer)
    }
}

class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) {
        // Remove existing layer if different
        if previewLayer !== layer {
            previewLayer?.removeFromSuperlayer()
            previewLayer = layer

            if let layer = layer {
                layer.frame = bounds
                layer.videoGravity = .resizeAspectFill
                self.layer.addSublayer(layer)
            }
        } else {
            // Just update frame
            previewLayer?.frame = bounds
        }
    }
}
