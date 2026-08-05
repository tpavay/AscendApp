import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    @State private var settingsManager = SettingsManager.shared
    @State private var profileData: UserDisplayNameData?
    @State private var isLoadingProfile = true
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var imageForCropping: UIImage?
    @State private var showingCropView = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                profilePictureSection

                if isLoadingProfile {
                    ProgressView()
                        .tint(.accent)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Loading profile")
                } else {
                    profileSection
                    personalInformationSection
                    locationSection
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
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
        .onChange(of: selectedPhotoItem) { _, newValue in
            if let newValue {
                Task {
                    await loadImageForCropping(newValue)
                }
            }
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") {
                authVM.errorMessage = nil
            }
        } message: {
            Text(authVM.errorMessage ?? "Try again.")
        }
        .onAppear {
            Task {
                await loadProfile()
            }
        }
        .onChange(of: authVM.authenticationState) { _, newValue in
            if newValue == .unauthenticated {
                dismiss()
            }
        }
    }

    private var profilePictureSection: some View {
        VStack(spacing: 16) {
            ZStack {
                profileImageView

                if isUploadingPhoto {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 120, height: 120)

                        ProgressView()
                            .tint(.white)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Uploading profile photo")
                }
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("Change Photo")
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
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
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 2)
                    }
            case .failure:
                placeholderImage
            @unknown default:
                placeholderImage
            }
        }
        .frame(width: 120, height: 120)
        .accessibilityLabel("Profile photo")
    }

    private var placeholderImage: some View {
        ZStack {
            Circle()
                .fill(.jetLighter.opacity(0.3))

            Image(systemName: "person.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
        }
        .frame(width: 120, height: 120)
    }

    private var profileSection: some View {
        ProfileSection(title: "Profile") {
            ProfileCardSurface {
                VStack(spacing: 0) {
                    ProfileValueRow(
                        icon: .settingsEditProfile,
                        title: "First name",
                        value: displayValue(profileData?.firstName),
                        destination: ProfileNameEditorView(
                            field: .firstName,
                            firstName: profileData?.firstName ?? "",
                            lastName: profileData?.lastName ?? ""
                        )
                    )

                    ProfileCardDivider(leadingInset: 60)

                    ProfileValueRow(
                        icon: .settingsEditProfile,
                        title: "Last name",
                        value: displayValue(profileData?.lastName),
                        destination: ProfileNameEditorView(
                            field: .lastName,
                            firstName: profileData?.firstName ?? "",
                            lastName: profileData?.lastName ?? ""
                        )
                    )
                }
            }
        }
    }

    private var personalInformationSection: some View {
        ProfileSection(title: "Personal Information") {
            ProfileCardSurface {
                VStack(spacing: 0) {
                    ProfileValueRow(
                        icon: .profileBirthday,
                        title: "Birthday",
                        value: formattedBirthday,
                        destination: ProfileBirthdayEditorView(birthday: profileData?.birthday)
                    )

                    ProfileCardDivider(leadingInset: 60)

                    ProfileValueRow(
                        icon: .profileGender,
                        title: "Gender",
                        value: formattedGender,
                        destination: ProfileGenderEditorView(
                            gender: profileData?.gender.flatMap(ProfileGender.init(rawValue:))
                        )
                    )

                    ProfileCardDivider(leadingInset: 60)

                    ProfileValueRow(
                        icon: .settingsMeasurementSystem,
                        title: "Height",
                        value: formattedHeight,
                        destination: BodyMetricsEditorView()
                    )

                    ProfileCardDivider(leadingInset: 60)

                    ProfileValueRow(
                        icon: .profileWeight,
                        title: "Weight",
                        value: formattedWeight,
                        destination: BodyMetricsEditorView()
                    )
                }
            }
        }
    }

    private var locationSection: some View {
        ProfileSection(title: "Location") {
            ProfileCardSurface {
                ProfileValueRow(
                    icon: .mapPin,
                    title: "Location",
                    value: formattedLocation,
                    destination: ProfileLocationEditorView(
                        city: profileData?.locationCity,
                        region: profileData?.locationRegion,
                        countryCode: profileData?.locationCountry
                    )
                )
            }
        }
    }

    private var formattedBirthday: String {
        guard let date = profileData?.birthday?.date() else { return "Not set" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var formattedGender: String {
        profileData?.gender
            .flatMap(ProfileGender.init(rawValue:))?
            .displayName ?? "Not set"
    }

    private var formattedHeight: String {
        guard let heightCm = profileData?.heightCm, heightCm > 0 else { return "Not set" }

        switch settingsManager.measurementSystem {
        case .imperial:
            let totalInches = max(
                Int(MeasurementSystem.metric.convertHeight(heightCm, to: .imperial).rounded()),
                0
            )
            return "\(totalInches / 12) ft \(totalInches % 12) in"
        case .metric:
            return "\(Int(heightCm.rounded())) cm"
        }
    }

    private var formattedWeight: String {
        guard let weightKg = profileData?.weightKg, weightKg > 0 else { return "Not set" }
        let converted = MeasurementSystem.metric.convertWeight(
            weightKg,
            to: settingsManager.measurementSystem
        )
        return settingsManager.measurementSystem.formatWeight(converted)
    }

    private var formattedLocation: String {
        guard let city = profileData?.locationCity, !city.isEmpty else { return "Not set" }
        if let region = profileData?.locationRegion, !region.isEmpty {
            return "\(city), \(region)"
        }
        return city
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { authVM.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    authVM.errorMessage = nil
                }
            }
        )
    }

    private func displayValue(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "Not set"
        }
        return value
    }

    private func loadProfile() async {
        guard let userID = authVM.user?.uid else {
            isLoadingProfile = false
            return
        }

        do {
            profileData = try await UserDataRepository.shared.getUserFromFirestore(userId: userID)
        } catch {
            authVM.errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
        isLoadingProfile = false
    }

    private func loadImageForCropping(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            authVM.errorMessage = "Failed to load image"
            selectedPhotoItem = nil
            return
        }

        imageForCropping = image
        showingCropView = true
        selectedPhotoItem = nil
    }

    private func uploadCroppedImage(_ image: UIImage) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            authVM.errorMessage = "Failed to process image"
            return
        }

        await authVM.updateProfilePictureWithData(imageData: imageData)
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
            .environment(AuthenticationViewModel())
    }
}
