//
//  SwiftUIView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import SwiftUI
import PhotosUI

struct PhotoPickerButton: View {
    enum Style {
        case expandedDropzone
        case inlineTile

        var fillsWidth: Bool {
            switch self {
            case .expandedDropzone:
                return true
            case .inlineTile:
                return false
            }
        }

        var width: CGFloat? {
            switch self {
            case .expandedDropzone:
                return nil
            case .inlineTile:
                return 120
            }
        }

        var height: CGFloat { 120 }

        var cornerRadius: CGFloat {
            switch self {
            case .expandedDropzone:
                return 8
            case .inlineTile:
                return 12
            }
        }
    }

    @Binding var selectedPhotos: [PhotosPickerItem]
    var isLoading: Bool = false
    var style: Style = .expandedDropzone

    var body: some View {
        PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(.accent,
                        style: StrokeStyle(lineWidth: 1, dash:[10, 5])
                )
                .frame(maxWidth: style.fillsWidth ? .infinity : nil)
                .frame(width: style.width, height: style.height)
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
