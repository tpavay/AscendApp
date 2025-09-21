//
//  ThumbnailPhotoView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import SwiftUI

struct ThumbnailPhotoView: View {
    let photoItem: SelectedPhotoItem
    let onDelete: () -> Void

    var body: some View {
     photoItem.image
         .resizable()
         .aspectRatio(contentMode: .fill)
         .frame(width: 120, height: 120)
         .clipShape(RoundedRectangle(cornerRadius: 8))
         .onTapGesture {
             onDelete()
         }
    }
}
