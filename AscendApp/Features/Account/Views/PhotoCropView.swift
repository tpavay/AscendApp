//
//  PhotoCropView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//

import SwiftUI
import PhotosUI

struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let image: UIImage
    let onCrop: (UIImage) -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let cropSize: CGFloat = 300
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                Spacer()
                
                // Crop Area
                cropAreaView
                
                Spacer()
                
                // Instructions
                instructionsView
                
                // Action Buttons
                actionButtons
            }
            .padding(.bottom, 20)
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .font(.montserratMedium(size: 16))
            .foregroundStyle(.white)
            
            Spacer()
            
            Text("Move and Scale")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(.white)
            
            Spacer()
            
            // Empty space to balance the layout
            Text("")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.clear)
                .frame(width: 60)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 20)
    }
    
    // MARK: - Crop Area
    
    private var cropAreaView: some View {
        ZStack {
            // The image that can be moved and scaled
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cropSize, height: cropSize)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale *= delta
                            
                            // Limit scale
                            scale = min(max(scale, 1.0), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                        .simultaneously(with: DragGesture()
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
                .clipShape(Circle())
            
            // Circle overlay to show crop area
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: cropSize, height: cropSize)
            
            // Outer shadow/dim effect
            Circle()
                .strokeBorder(Color.black.opacity(0.5), lineWidth: 100)
                .frame(width: cropSize + 200, height: cropSize + 200)
        }
        .frame(width: cropSize, height: cropSize)
    }
    
    // MARK: - Instructions
    
    private var instructionsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Drag to move")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            HStack(spacing: 16) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Pinch to zoom")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.vertical, 30)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button(action: resetPosition) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                )
            }
            
            Button(action: cropImage) {
                Text("Apply")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accent)
                    )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Actions
    
    private func resetPosition() {
        withAnimation(.spring(response: 0.3)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    private func cropImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropSize, height: cropSize))
        
        let croppedImage = renderer.image { context in
            // Create circular clipping path
            let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: cropSize, height: cropSize))
            path.addClip()
            
            // Calculate the image rect to match .scaledToFill behavior
            let imageSize = image.size
            let imageAspect = imageSize.width / imageSize.height
            let viewAspect: CGFloat = 1.0 // Square crop area
            
            var drawWidth: CGFloat
            var drawHeight: CGFloat
            
            // This matches SwiftUI's .scaledToFill() behavior
            if imageAspect > viewAspect {
                // Image is wider - fit height and overflow width
                drawHeight = cropSize
                drawWidth = drawHeight * imageAspect
            } else {
                // Image is taller - fit width and overflow height
                drawWidth = cropSize
                drawHeight = drawWidth / imageAspect
            }
            
            // Apply scale
            drawWidth *= scale
            drawHeight *= scale
            
            // Center the image and apply offset
            let x = (cropSize - drawWidth) / 2 + offset.width
            let y = (cropSize - drawHeight) / 2 + offset.height
            
            // Draw the image
            image.draw(in: CGRect(x: x, y: y, width: drawWidth, height: drawHeight))
        }
        
        onCrop(croppedImage)
        dismiss()
    }
}

#Preview {
    PhotoCropView(
        image: UIImage(systemName: "person.fill")!,
        onCrop: { _ in }
    )
}

