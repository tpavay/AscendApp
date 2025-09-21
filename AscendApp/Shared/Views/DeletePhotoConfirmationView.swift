//
//  DeletePhotoConfirmationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import SwiftUI

struct DeletePhotoConfirmationView: View {
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ConfirmationView(
            title: "Delete Photo?",
            message: "This action cannot be undone.",
            confirmButtonText: "Delete",
            isDestructive: true,
            onCancel: onCancel,
            onConfirm: onDelete
        )
        .presentationDetents([.height(180)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    DeletePhotoConfirmationView(
        onDelete: { print("Photo deleted") },
        onCancel: { print("Cancelled") }
    )
}
