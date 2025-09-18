//
//  SelectedImage.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/13/25.
//

import Foundation
import PhotosUI
import SwiftUI

struct SelectedImage: Identifiable, Equatable {
    var id = UUID()
    var item: PhotosPickerItem
    var image: Image?
    var localIdentifier: String
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
}