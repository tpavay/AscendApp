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

    var body: some View {
        PhotosPicker(selection: $selectedPhotos, matching: .images) {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.accent,
                        style: StrokeStyle(lineWidth: 1, dash:[10, 5])
                )
                .frame(height: 120)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "camera")
                        Text("Add Photos")
                            .font(.caption)
                    }
                }
        }
    }
}
