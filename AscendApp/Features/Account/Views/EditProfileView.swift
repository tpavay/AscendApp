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

    @State private var settingsManager = SettingsManager.shared
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var imageForCropping: UIImage?
    @State private var showingCropView = false
    @State private var isEditingDisplayName = false
    @State private var editedDisplayName = ""
    @State private var isSavingDisplayName = false
    @State private var showingFitnessLevelSheet = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var showingSignOutConfirmation = false
    @FocusState private var isDisplayNameFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Profile Picture Section
                profilePictureSection

                // User Info Section
                userInfoSection

                // Fitness Level Section
                fitnessLevelSection

                // Preferences Section
                preferencesSection

                // Account actions
                accountActionsSection

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingSignOutConfirmation = true
                } label: {
                    Text("Sign Out")
                }
                .font(.montserratSemiBold(size: 15))
                .buttonStyle(.plain)
            }
            ToolbarItemGroup(placement: .keyboard) {
                if isEditingDisplayName {
                    Button("Cancel") {
                        cancelEditing()
                    }

                    Spacer()

                    if isSavingDisplayName {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Done") {
                            saveDisplayName()
                        }
                        .disabled(editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
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
        .sheet(isPresented: $showingFitnessLevelSheet) {
            FitnessLevelSheetView(settingsManager: settingsManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingDeleteAccountConfirmation) {
            DeleteAccountConfirmationView(
                onAccountDeleted: {
                    dismiss()
                }
            )
        }
        .alert(
            "Sign Out",
            isPresented: $showingSignOutConfirmation,
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authVM.signOut()
            }
        } message: {
            Text("You'll need to sign back in to access your account.")
        }
        .onChange(of: authVM.authenticationState) { _, newValue in
            if newValue == .unauthenticated {
                dismiss()
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
        ProfileSection(title: "Profile Information") {
            ProfileCardSurface {
                VStack(spacing: 0) {
                    displayNameRow

                    if let email = authVM.user?.email {
                        ProfileCardDivider()
                        InfoRow(label: "Email", value: email)
                    }
                }
            }
        }
    }

    // MARK: - Fitness Level Section

    private var fitnessLevelSection: some View {
        ProfileSection(title: "Fitness Level") {
            ProfileCardSurface {
                Button {
                    showingFitnessLevelSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: settingsManager.fitnessLevel.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.accent)

                        Text(settingsManager.fitnessLevel.displayName)
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        Spacer()

                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundStyle(.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var preferencesSection: some View {
        ProfileSection(title: "Preferences") {
            SettingsCard(options: preferenceOptions)
        }
    }

    private var accountActionsSection: some View {
        ProfileSection(title: "Account") {
            SettingsCard(options: accountOptions)
        }
    }

    private var preferenceOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsAppearance,
                title: "Appearance",
                destination: ThemeSelectionView()
            ),
            SettingsOption(
                icon: .settingsWorkoutMetric,
                title: "Workout Metric",
                destination: WorkoutMetricSelectionView()
            ),
            SettingsOption(
                icon: .settingsMeasurementSystem,
                title: "Measurement System",
                destination: MeasurementSystemSelectionView()
            ),
            SettingsOption(
                icon: .settingsEditProfile,
                title: "Body & Profile Data",
                destination: OnboardingProfileSettingsView()
            ),
            SettingsOption(
                icon: .settingsWeekStart,
                title: "Week Starts On",
                destination: WeekStartSelectionView()
            ),
            SettingsOption(
                icon: .settingsIntegrations,
                title: "Integrations",
                destination: IntegrationsView()
            )
        ]
    }

    private var accountOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsDeleteAccount,
                title: "Delete Account",
                isDestructive: true,
                action: {
                    isShowingDeleteAccountConfirmation = true
                }
            )
        ]
    }
    
    private var displayNameRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Name")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.secondary)
            
            if isEditingDisplayName {
                TextField("Enter display name", text: $editedDisplayName)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .textFieldStyle(.plain)
                    .focused($isDisplayNameFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        saveDisplayName()
                    }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Fitness Level Sheet

private struct FitnessLevelSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Bindable var settingsManager: SettingsManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    ForEach(FitnessLevel.allCases) { level in
                        fitnessLevelRow(level: level)
                    }
                }
                .padding(.horizontal, 20)

                // Info text
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Text("Sets initial scoring thresholds for your first 10 workouts, then transitions to personalized scoring.")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 20)
            .themedBackground()
            .navigationTitle("Fitness Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.montserratSemiBold(size: 16))
                }
            }
        }
    }

    private func fitnessLevelRow(level: FitnessLevel) -> some View {
        Button(action: {
            settingsManager.setFitnessLevel(level)
        }) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.jetLighter.opacity(0.3) : Color.gray.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: level.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.accent)
                }

                // Text Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(level.description)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(colorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if settingsManager.fitnessLevel == level {
                        Circle()
                            .fill(.accent)
                            .frame(width: 14, height: 14)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settingsManager.fitnessLevel)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.jetLighter.opacity(0.3) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settingsManager.fitnessLevel == level ? .accent.opacity(0.5) : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
            .environment(AuthenticationViewModel())
    }
}
