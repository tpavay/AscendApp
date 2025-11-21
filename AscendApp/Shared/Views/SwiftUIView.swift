//
//  SwiftUIView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import SwiftUI
import PhotosUI

struct PhotoPickerButton: View {
    @Binding var selectedPhotos: [PhotosPickerItem]
    var isLoading: Bool = false

    var body: some View {
        PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.accent,
                        style: StrokeStyle(lineWidth: 1, dash:[10, 5])
                )
                .frame(height: 120)
                .overlay {
                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.accent)
                            Text("Loading Media")
                                .font(.caption)
                                .foregroundStyle(.accent)
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "camera")
                                .foregroundStyle(.accent)
                            Text("Add Media")
                                .font(.caption)
                                .foregroundStyle(.accent)
                        }
                    }
                }
        }
        .disabled(isLoading)
    }
}
