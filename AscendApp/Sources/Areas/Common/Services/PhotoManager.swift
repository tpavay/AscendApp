//
//  PhotoManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/13/25.
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
class PhotoManager: ObservableObject {
    
    /// Processes PhotosPickerItems into SelectedImage objects with proper orientation
    static func processItems(_ items: [PhotosPickerItem]) async -> [SelectedImage] {
        var selectedImages: [SelectedImage] = []
        
        for (index, item) in items.enumerated() {
            let identifier = item.itemIdentifier ?? "item_\(index)"
            
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let orientationFixedImage = uiImage.fixedOrientation()
                let swiftUIImage = Image(uiImage: orientationFixedImage)
                
                let selectedImage = SelectedImage(
                    item: item,
                    image: swiftUIImage,
                    localIdentifier: identifier
                )
                selectedImages.append(selectedImage)
            }
        }
        
        return selectedImages
    }
    
    /// Removes a SelectedImage from both display array and PhotosPickerItems
    static func deleteImage(_ imageToDelete: SelectedImage, 
                           from selectedImages: inout [SelectedImage], 
                           and selectedItems: inout [PhotosPickerItem]) {
        // Remove from displayed images (SwiftUI will efficiently update ForEach)
        selectedImages.removeAll { $0.id == imageToDelete.id }
        
        // Keep PhotosPicker selection in sync
        selectedItems.removeAll { $0.itemIdentifier == imageToDelete.localIdentifier }
    }
}

// MARK: - UIImage Extension
extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
}