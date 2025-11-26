//
//  EditProfileView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var imageForCropping: UIImage?
    @State private var showingCropView = false
    @State private var isEditingDisplayName = false
    @State private var editedDisplayName = ""
    @State private var isSavingDisplayName = false
    @FocusState private var isDisplayNameFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Profile Picture Section
                profilePictureSection
                
                // User Info Section
                userInfoSection
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .themedBackground()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingCropView) {
            if let image = imageForCropping {
                PhotoCropView(image: image) { croppedImage in
                    Task {
                        await uploadCroppedImage(croppedImage)
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            if let newValue = newValue {
                Task {
                    await loadImageForCropping(newValue)
                }
            }
        }
        .alert("Error", isPresented: .constant(authVM.errorMessage != nil)) {
            Button("OK") {
                authVM.errorMessage = nil
            }
        } message: {
            if let errorMessage = authVM.errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Profile Picture Section
    
    private var profilePictureSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Profile Image
                profileImageView
                
                // Loading overlay
                if isUploadingPhoto {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 120, height: 120)
                        
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            
            // Change Photo Button
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("Change Photo")
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
            }
            .disabled(isUploadingPhoto)
        }
    }
    
    private var profileImageView: some View {
        AsyncImage(url: authVM.displayPhotoURL) { phase in
            switch phase {
            case .empty:
                placeholderImage
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 2)
                    )
            case .failure:
                placeholderImage
            @unknown default:
                placeholderImage
            }
        }
        .frame(width: 120, height: 120)
    }
    
    private var placeholderImage: some View {
        ZStack {
            Circle()
                .fill(.jetLighter.opacity(0.3))
                .frame(width: 120, height: 120)
            
            Image(systemName: "person.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
    
    // MARK: - User Info Section
    
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile Information")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            // Display Name (Editable)
            displayNameRow
            
            // Email
            if let email = authVM.user?.email {
                InfoRow(label: "Email", value: email)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var displayNameRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Name")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.secondary)
            
            if isEditingDisplayName {
                HStack(spacing: 12) {
                    TextField("Enter display name", text: $editedDisplayName)
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .textFieldStyle(.plain)
                        .focused($isDisplayNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            saveDisplayName()
                        }
                    
                    if isSavingDisplayName {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            saveDisplayName()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.accent)
                        }
                        .disabled(editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Button {
                            cancelEditing()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.jetLighter.opacity(0.3) : Color.gray.opacity(0.1))
                )
            } else {
                Button {
                    startEditing()
                } label: {
                    HStack {
                        Text(authVM.displayName.isEmpty ? "Not Set" : authVM.displayName)
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        
                        Spacer()
                        
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundStyle(.accent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.jetLighter.opacity(0.3) : Color.gray.opacity(0.1))
                    )
                }
            }
        }
    }
    
    private func startEditing() {
        editedDisplayName = authVM.displayName
        isEditingDisplayName = true
        isDisplayNameFocused = true
    }
    
    private func cancelEditing() {
        isEditingDisplayName = false
        editedDisplayName = ""
        isDisplayNameFocused = false
    }
    
    private func saveDisplayName() {
        let trimmedName = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        isSavingDisplayName = true
        
        Task {
            await authVM.updateDisplayName(trimmedName)
            isSavingDisplayName = false
            isEditingDisplayName = false
            isDisplayNameFocused = false
        }
    }
    
    // MARK: - Actions
    
    private func loadImageForCropping(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            authVM.errorMessage = "Failed to load image"
            selectedPhotoItem = nil
            return
        }
        
        imageForCropping = uiImage
        showingCropView = true
        selectedPhotoItem = nil
    }
    
    private func uploadCroppedImage(_ image: UIImage) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        
        // Convert UIImage to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            authVM.errorMessage = "Failed to process image"
            return
        }
        
        await authVM.updateProfilePictureWithData(imageData: imageData)
    }
}

// MARK: - Info Row Component

private struct InfoRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.montserratRegular(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.jetLighter.opacity(0.3) : Color.gray.opacity(0.1))
        )
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
            .environment(AuthenticationViewModel())
    }
}

