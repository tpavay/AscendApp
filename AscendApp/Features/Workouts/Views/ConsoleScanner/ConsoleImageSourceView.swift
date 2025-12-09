//
//  ConsoleImageSourceView.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI
import PhotosUI
import AVFoundation

/// View with live camera preview and crop frame overlay for scanning console
struct ConsoleImageSourceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @Bindable var viewModel: ConsoleScanViewModel

    // Camera state
    @State private var cameraManager = CameraManager()

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

                // Camera preview clipped to crop box
                CameraPreviewView(cameraManager: cameraManager)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8)
                            .size(width: cropBoxSize.width, height: cropBoxSize.height)
                            .offset(
                                x: (geometry.size.width - cropBoxSize.width) / 2,
                                y: (geometry.size.height - cropBoxSize.height) / 2
                            )
                    )

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
                        // Take Photo button
                        Button {
                            capturePhoto(cropBoxSize: cropBoxSize, containerSize: geometry.size)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                Text("Take Photo")
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
                        PhotosPicker(
                            selection: $viewModel.selectedPhotoItem,
                            matching: .images
                        ) {
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
            Task {
                await cameraManager.requestPermissionAndSetup()
            }
        }
        .onDisappear {
            cameraManager.stopSession()
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

    /// Capture photo and crop to frame bounds
    private func capturePhoto(cropBoxSize: CGSize, containerSize: CGSize) {
        cameraManager.capturePhoto { image in
            guard let image = image else { return }

            // Crop the captured image to the frame area
            if let croppedImage = cropImageToFrame(
                image: image,
                cropBoxSize: cropBoxSize,
                containerSize: containerSize
            ) {
                // Skip crop view, go straight to processing
                viewModel.processCroppedImage(croppedImage)
            } else {
                // Fallback: use full image and go to crop view
                viewModel.handleCameraCapture(image)
            }
        }
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

@MainActor
@Observable
class CameraManager: NSObject {
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var captureCompletion: ((UIImage?) -> Void)?

    var isSessionRunning = false
    var previewLayer: AVCaptureVideoPreviewLayer?

    func requestPermissionAndSetup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                setupSession()
            }
        default:
            break
        }
    }

    private func setupSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = session.isRunning
            }
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil)
            return
        }

        captureCompletion = completion

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
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                captureCompletion?(nil)
                captureCompletion = nil
            }
            return
        }

        Task { @MainActor in
            captureCompletion?(image)
            captureCompletion = nil
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager

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
