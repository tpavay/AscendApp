//
//  SingleWorkoutDeleteConfirmationView.swift
//  AscendApp
//
import SwiftUI

struct SingleWorkoutDeleteConfirmationView: View {
    let workout: Workout
    let isLoading: Bool
    let isCancelling: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ConfirmationView(
            title: "Delete Workout",
            message: "Are you sure you want to delete \"\(workout.name)\"? This action cannot be undone.",
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
