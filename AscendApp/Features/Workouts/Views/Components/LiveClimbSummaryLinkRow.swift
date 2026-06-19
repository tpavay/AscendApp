//
//  LiveClimbSummaryLinkRow.swift
//  AscendApp
//
import SwiftUI

struct LiveClimbSummaryLinkRow: View {
    let climb: Climb?
    let effectiveColorScheme: ColorScheme
    let onViewSummary: () -> Void

    var body: some View {
        Button(action: onViewSummary) {
            HStack(spacing: 14) {
                leadingArtwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(climb?.name ?? "Live Climb Summary")
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    Text("View saved summary")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .accessibilityLabel("View Live Climb summary")
        .accessibilityHint("Opens the saved Live Climb summary for this workout.")
    }

    @ViewBuilder
    private var leadingArtwork: some View {
        if let climb {
            ClimbArtworkView(climb: climb, variant: .thumb)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(effectiveColorScheme == .dark ? 0.10 : 0.08), lineWidth: 1)
                )
        } else {
            AppIcon(token: .mountains, pointSize: 20, weight: .medium)
                .foregroundStyle(primaryTextColor.opacity(0.74))
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(effectiveColorScheme == .dark ? .white.opacity(0.07) : .black.opacity(0.05))
                )
        }
    }

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48)
    }

    private var cardBackground: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06)
    }

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }
}
