//
//  SelectedPhotoItem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import Foundation
import PhotosUI
import SwiftUI

struct SelectedPhotoItem: Identifiable {
    let id = UUID()
    let pickerItem: PhotosPickerItem
    let image: Image
    let localIdentifier: String
}
