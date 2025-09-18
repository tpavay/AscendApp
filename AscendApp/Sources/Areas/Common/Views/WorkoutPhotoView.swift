//
//  WorkoutPhotoView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/13/25.
//

import SwiftUI
import PhotosUI

struct WorkoutPhotoView: View {
    let selectedImage: SelectedImage
    let onTap: () -> Void
    
    var body: some View {
        if let image = selectedImage.image {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)
                .cornerRadius(8)
                .onTapGesture {
                    onTap()
                }
        }
    }
}

#Preview {
    // Create a mock PhotosPickerItem for preview
    let mockItem = PhotosPickerItem.init(itemIdentifier: "preview-item")

    WorkoutPhotoView(
        selectedImage: SelectedImage(
            item: mockItem,
            image: Image(systemName: "photo"),
            localIdentifier: "preview"
        ),
        onTap: {}
    )
}
