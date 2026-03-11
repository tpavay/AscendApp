//
//  DeleteWorkoutConfirmationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/21/25.
//

import SwiftUI

struct DeleteWorkoutConfirmationView: View {
    let selectedCount: Int
    let isLoading: Bool
    let isCancelling: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ConfirmationView(
            title: "Delete Workout\(selectedCount == 1 ? "" : "s")",
            message: "Are you sure you want to delete \(selectedCount) workout\(selectedCount == 1 ? "" : "s")? This action cannot be undone.",
            confirmButtonText: "Delete",
            isDestructive: true,
            isLoading: isLoading,
            isCancelling: isCancelling,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
        .appSheetStyle(.destructiveConfirmation)
    }
}

#Preview {
    DeleteWorkoutConfirmationView(
        selectedCount: 3,
        isLoading: false,
        isCancelling: false,
        onConfirm: { print("Delete confirmed") },
        onCancel: { print("Delete cancelled") }
    )
}

#Preview("Loading") {
    DeleteWorkoutConfirmationView(
        selectedCount: 1,
        isLoading: true,
        isCancelling: false,
        onConfirm: { print("Delete confirmed") },
        onCancel: { print("Delete cancelled") }
    )
}

#Preview("Cancelling") {
    DeleteWorkoutConfirmationView(
        selectedCount: 1,
        isLoading: true,
        isCancelling: true,
        onConfirm: { print("Delete confirmed") },
        onCancel: { print("Delete cancelled") }
    )
}
