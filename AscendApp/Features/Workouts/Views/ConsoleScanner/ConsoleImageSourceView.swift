//
//  ConsoleImageSourceView.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI
import PhotosUI

/// View for selecting image source (camera or photo library)
struct ConsoleImageSourceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @Bindable var viewModel: ConsoleScanViewModel

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)

                Text("Scan Console")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("Take a photo of your stair stepper console to automatically log your workout")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 40)

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                // Take Photo button
                Button {
                    viewModel.showingCamera = true
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
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, _ in
            Task {
                await viewModel.handlePhotoSelection()
            }
        }
        .fullScreenCover(isPresented: $viewModel.showingCamera) {
            CameraView(onCapture: { image in
                viewModel.handleCameraCapture(image)
            })
        }
    }
}

// MARK: - Camera View

/// UIKit camera wrapper for SwiftUI
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .rear
        picker.cameraFlashMode = .off // LED displays are self-lit
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
