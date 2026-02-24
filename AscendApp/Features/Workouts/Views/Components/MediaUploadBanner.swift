//
//  MediaUploadBanner.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/11/26.
//

import SwiftUI

/// Banner displaying media upload status for a workout.
/// Shows uploading progress, failed state with retry, or nothing when complete.
struct MediaUploadBanner: View {
    let workoutId: UUID
    let onRetry: () -> Void

    // Observe manager via environment for proper SwiftUI reactivity
    @Environment(MediaUploadManager.self) private var uploadManager

    var body: some View {
        let status = uploadManager.uploadStatus(for: workoutId)

        switch status {
        case .none:
            EmptyView()

        case .uploading(let current, let total):
            uploadingBanner(current: current, total: total)

        case .failed(let count):
            failedBanner(count: count)
        }
    }

    // MARK: - Uploading Banner

    @ViewBuilder
    private func uploadingBanner(current: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)

            Text("Uploading media (\(current)/\(total))...")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()
        }
        .padding()
        .background(Color.blue)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Failed Banner

    @ViewBuilder
    private func failedBanner(count: Int) -> some View {
        Button(action: onRetry) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) upload\(count == 1 ? "" : "s") failed")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Tap to retry")
                        .font(.caption)
                        .opacity(0.9)
                }

                Spacer()

                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
        }
        .padding()
        .background(Color.orange)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 16) {
        // Note: These won't render properly without environment setup
        // Just for layout preview
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Uploading media (1/3)...")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding()
        .background(Color.blue)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 12))

        Button(action: {}) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("2 uploads failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Tap to retry")
                        .font(.caption)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
        }
        .padding()
        .background(Color.orange)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 12))
    }
    .padding()
}
