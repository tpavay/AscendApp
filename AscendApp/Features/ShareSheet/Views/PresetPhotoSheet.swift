import PhotosUI
import SwiftUI

/// The single-photo background picker: photos taken during the climb first, then earlier ones,
/// then the full library. One tap selects and closes.
struct PresetPhotoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: PresetsViewModel
    let climbWindow: DateInterval

    @State private var library = PresetPhotoLibrary()
    @State private var pickerItem: PhotosPickerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { dismiss() }
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(Color(shareHex: 0xA3A3A3))
                Spacer()
                Text("Photo background")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if library.access == .denied {
                        Text("Allow Photos access in Settings to use a photo.")
                            .font(.montserratMedium(size: 13))
                            .foregroundStyle(Color(shareHex: 0xA3A3A3))
                    }
                    if !library.duringClimb.isEmpty {
                        section("DURING THIS CLIMB", photos: library.duringClimb)
                    }
                    if !library.earlier.isEmpty {
                        section("EARLIER", photos: library.earlier)
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("All photos", systemImage: "photo.on.rectangle")
                            .font(.montserratBold(size: 14))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Capsule().fill(Color(shareHex: PresetAccent.lime.hex)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .task {
            await library.load(climbWindow: climbWindow)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    model.selectPhoto(image)
                    dismiss()
                }
            }
        }
    }

    private func section(_ title: String, photos: [PresetPhotoLibrary.Photo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.montserratBold(size: 11))
                .tracking(1.5)
                .foregroundStyle(Color(shareHex: 0xA3A3A3))
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(photos) { photo in
                    PresetPhotoTile(photo: photo, library: library) { image in
                        model.selectPhoto(image)
                        dismiss()
                    }
                }
            }
        }
    }
}
