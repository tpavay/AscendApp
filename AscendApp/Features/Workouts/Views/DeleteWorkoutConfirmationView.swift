//
//  DeleteWorkoutConfirmationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/21/25.
//

import SwiftUI

struct DeleteWorkoutConfirmationView: View {
    let selectedCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ConfirmationView(
            title: "Delete Workout\(selectedCount == 1 ? "" : "s")",
            message: "Are you sure you want to delete \(selectedCount) workout\(selectedCount == 1 ? "" : "s")? This action cannot be undone.",
            confirmButtonText: "Delete",
            isDestructive: true,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }
}

#Preview {
    DeleteWorkoutConfirmationView(
        selectedCount: 3,
        onConfirm: { print("Delete confirmed") },
        onCancel: { print("Delete cancelled") }
    )
}
