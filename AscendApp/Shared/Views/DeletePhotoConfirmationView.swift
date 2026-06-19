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
        .appSheetStyle(.compactConfirmation)
    }
}

#Preview {
    DeletePhotoConfirmationView(
        onDelete: { debugLog("Photo deleted") },
        onCancel: { debugLog("Cancelled") }
    )
}
