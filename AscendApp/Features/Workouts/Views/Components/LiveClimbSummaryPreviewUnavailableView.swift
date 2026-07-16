//
//  LiveClimbSummaryPreviewUnavailableView.swift
//  AscendApp
//
import SwiftUI

struct LiveClimbSummaryPreviewUnavailableView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.accent)

            VStack(spacing: 8) {
                Text("Summary unavailable")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)

                Text("This workout has Live Climb metadata, but its climb could not be loaded.")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button(action: onDismiss) {
                Text("Done")
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.black)
                    .frame(width: 160, height: 48)
                    .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
