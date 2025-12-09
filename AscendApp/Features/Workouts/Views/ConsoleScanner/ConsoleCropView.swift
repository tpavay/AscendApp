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
        guard let cgImage = image.cgImage else { return nil }

        let imageSize = image.size

        // Calculate the visible image size on screen
        let aspectRatio = imageSize.width / imageSize.height
        var displayedSize: CGSize
        if aspectRatio > containerSize.width / containerSize.height {
            displayedSize = CGSize(
                width: containerSize.width,
                height: containerSize.width / aspectRatio
            )
        } else {
            displayedSize = CGSize(
                width: containerSize.height * aspectRatio,
                height: containerSize.height
            )
        }

        // Apply scale
        displayedSize.width *= scale
        displayedSize.height *= scale

        // Calculate the center of the crop box in container coordinates
        let cropBoxCenter = CGPoint(
            x: containerSize.width / 2,
            y: containerSize.height / 2
        )

        // Calculate the image center after offset
        let imageCenter = CGPoint(
            x: containerSize.width / 2 + offset.width,
            y: containerSize.height / 2 + offset.height
        )

        // Calculate crop box position relative to image
        let cropBoxInImage = CGPoint(
            x: (cropBoxCenter.x - imageCenter.x + displayedSize.width / 2) / displayedSize.width,
            y: (cropBoxCenter.y - imageCenter.y + displayedSize.height / 2) / displayedSize.height
        )

        // Convert to actual image pixels
        let cropRectOrigin = CGPoint(
            x: (cropBoxInImage.x - (cropBoxSize.width / displayedSize.width) / 2) * imageSize.width,
            y: (cropBoxInImage.y - (cropBoxSize.height / displayedSize.height) / 2) * imageSize.height
        )

        let cropRectSize = CGSize(
            width: (cropBoxSize.width / displayedSize.width) * imageSize.width,
            height: (cropBoxSize.height / displayedSize.height) * imageSize.height
        )

        // Clamp to image bounds
        var cropRect = CGRect(origin: cropRectOrigin, size: cropRectSize)
        cropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))

        // Validate minimum size (300x200 pixels)
        if cropRect.width < 300 || cropRect.height < 200 {
            return nil
        }

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

