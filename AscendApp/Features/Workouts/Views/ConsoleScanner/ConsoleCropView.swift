//
//  ConsoleCropView.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI

/// View for cropping the console image with a fixed bounding box
struct ConsoleCropView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    let image: UIImage
    @Bindable var viewModel: ConsoleScanViewModel

    // Gesture state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Crop box aspect ratio (16:9 for most console displays)
    private let cropAspectRatio: CGFloat = 16.0 / 9.0

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        GeometryReader { geometry in
            let cropBoxSize = calculateCropBoxSize(in: geometry.size)

            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Image clipped to crop box - only visible within the frame
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8)
                            .size(width: cropBoxSize.width, height: cropBoxSize.height)
                            .offset(
                                x: (geometry.size.width - cropBoxSize.width) / 2,
                                y: (geometry.size.height - cropBoxSize.height) / 2
                            )
                    )
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1.0), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )

                // Crop box border
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: cropBoxSize.width, height: cropBoxSize.height)

                // Instructions and buttons
                VStack {
                    // Top instruction
                    Text("Adjust the frame to capture your stats")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.top, 60)

                    Spacer()

                    // Bottom button
                    Button {
                        if let croppedImage = cropImage(
                            image: image,
                            cropBoxSize: cropBoxSize,
                            containerSize: geometry.size,
                            scale: scale,
                            offset: offset
                        ) {
                            viewModel.processCroppedImage(croppedImage)
                        }
                    } label: {
                        Text("Process Image")
                            .font(.montserratSemiBold(size: 16))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(viewModel.isProcessing)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }

                // Processing overlay
                if viewModel.isProcessing {
                    ProcessingOverlay()
                }
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

    /// Crop the image based on the visible area in the crop box
    private func cropImage(
        image: UIImage,
        cropBoxSize: CGSize,
        containerSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> UIImage? {
        // First, normalize the image orientation by redrawing it
        // This ensures CGImage pixels match the displayed orientation
        guard let normalizedImage = normalizeImageOrientation(image),
              let cgImage = normalizedImage.cgImage else {
            return nil
        }

        let imageSize = normalizedImage.size

        // Calculate the base displayed size when using .scaledToFit()
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        var baseDisplayedSize: CGSize
        if imageAspect > containerAspect {
            // Image is wider than container - width fills, height is smaller
            baseDisplayedSize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspect
            )
        } else {
            // Image is taller than container - height fills, width is smaller
            baseDisplayedSize = CGSize(
                width: containerSize.height * imageAspect,
                height: containerSize.height
            )
        }

        // Apply user's scale factor
        let scaledDisplayedSize = CGSize(
            width: baseDisplayedSize.width * scale,
            height: baseDisplayedSize.height * scale
        )

        // The image is centered in the container, then offset by user drag
        let imageCenterX = containerSize.width / 2 + offset.width
        let imageCenterY = containerSize.height / 2 + offset.height

        // Crop box is always centered in container
        let cropBoxCenterX = containerSize.width / 2
        let cropBoxCenterY = containerSize.height / 2

        // Calculate crop box bounds in container coordinates
        let cropBoxLeft = cropBoxCenterX - cropBoxSize.width / 2
        let cropBoxTop = cropBoxCenterY - cropBoxSize.height / 2

        // Calculate image bounds in container coordinates
        let imageLeft = imageCenterX - scaledDisplayedSize.width / 2
        let imageTop = imageCenterY - scaledDisplayedSize.height / 2

        // Calculate crop box position relative to the displayed image (0-1 normalized)
        let relativeX = (cropBoxLeft - imageLeft) / scaledDisplayedSize.width
        let relativeY = (cropBoxTop - imageTop) / scaledDisplayedSize.height
        let relativeWidth = cropBoxSize.width / scaledDisplayedSize.width
        let relativeHeight = cropBoxSize.height / scaledDisplayedSize.height

        // Convert to actual image pixel coordinates
        let cropRect = CGRect(
            x: relativeX * imageSize.width,
            y: relativeY * imageSize.height,
            width: relativeWidth * imageSize.width,
            height: relativeHeight * imageSize.height
        )

        // Clamp to image bounds
        let clampedRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))

        // Validate we have a reasonable crop area
        guard clampedRect.width >= 50 && clampedRect.height >= 50,
              let croppedCGImage = cgImage.cropping(to: clampedRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }

    /// Normalize image orientation by redrawing it with .up orientation
    /// This ensures CGImage pixel coordinates match displayed coordinates
    private func normalizeImageOrientation(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else {
            return image // Already normalized
        }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: image.size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

