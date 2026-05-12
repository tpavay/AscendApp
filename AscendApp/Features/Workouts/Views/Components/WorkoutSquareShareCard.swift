//
//  WorkoutSquareShareCard.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import SwiftUI

struct WorkoutSquareShareCard: View {
    let composition: WorkoutShareCardComposition

    private var layout: WorkoutShareCardPreset.Layout { composition.preset.layout }
    private var typography: WorkoutShareCardPreset.Typography { composition.preset.typography }
    private var header: WorkoutShareCardPreset.Header? { composition.preset.header }

    var body: some View {
        WorkoutShareCardSurface(surface: composition.preset.surface) {
            GeometryReader { geometry in
                content(in: geometry.size)
            }
        }
    }

    private func content(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            if header != nil {
                headerView(in: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            hero
                .frame(width: size.width * layout.heroWidthRatio)
                .padding(.top, layout.heroTopPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !composition.supportingStats.isEmpty {
                supportingStats
                    .frame(width: size.width * layout.supportingStatsWidthRatio)
                    .padding(.top, layout.supportingStatsTopPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if let bestEffortText = composition.bestEffortText {
                bestEffortFooter(bestEffortText)
                    .frame(width: size.width * 0.82)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func headerView(in size: CGSize) -> some View {
        if let header {
            ZStack {
                brandText(header.leadingText)
                    .position(x: size.width * header.leadingXRatio, y: header.textY)

                brandText(header.trailingText)
                    .position(x: size.width * header.trailingXRatio, y: header.textY)
            }
            .frame(width: size.width, height: header.height)
            .padding(.top, header.topPadding)
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Text(composition.heroStat.value)
                .font(WorkoutShareCardTypography.font(for: typography.heroValue))
                .tracking(typography.heroValue.tracking)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accent.opacity(1.0), .accent.opacity(0.56)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .shadow(color: .accent.opacity(0.22), radius: 22, x: 0, y: 12)
                .multilineTextAlignment(.center)

            Text(composition.heroStat.label)
                .font(WorkoutShareCardTypography.font(for: typography.heroLabel))
                .tracking(typography.heroLabel.tracking)
                .foregroundStyle(.accent.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.top, layout.heroLabelTopPadding)
        }
        .frame(maxWidth: .infinity)
    }

    private var supportingStats: some View {
        HStack(alignment: .top, spacing: layout.supportingStatsSpacing) {
            ForEach(Array(composition.supportingStats.enumerated()), id: \.element.id) { index, stat in
                WorkoutShareCardStatCell(stat: stat, typography: typography)
                    .frame(maxWidth: .infinity)

                if index < composition.supportingStats.count - 1 {
                    WorkoutShareCardDivider(
                        diamondSize: 5,
                        lineWidth: 1,
                        lineHeight: 28,
                        lineOpacity: 0.18
                    )
                }
            }
        }
    }

    private func brandText(_ text: String) -> some View {
        Text(text)
            .font(WorkoutShareCardTypography.font(for: typography.brand))
            .tracking(typography.brand.tracking)
            .foregroundStyle(.accent.opacity(0.68))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func bestEffortFooter(_ text: String) -> some View {
        HStack(spacing: 5) {
            AppIcon(token: .bestEffortTrophy, pointSize: 9, weight: .bold)
                .foregroundStyle(.accent.opacity(0.84))

            Text(text.uppercased())
                .font(.montserratBold(size: 7.2))
                .tracking(0.8)
                .foregroundStyle(.accent.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.black.opacity(0.24))
                .overlay(
                    Capsule()
                        .stroke(.accent.opacity(0.2), lineWidth: 0.8)
                )
        )
    }
}

private struct WorkoutShareCardStatCell: View {
    let stat: ShareCardResolvedStat
    let typography: WorkoutShareCardPreset.Typography

    var body: some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(WorkoutShareCardTypography.font(for: typography.statValue))
                .tracking(typography.statValue.tracking)
                .foregroundStyle(.accent.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(stat.label)
                .font(WorkoutShareCardTypography.font(for: typography.statLabel))
                .tracking(typography.statLabel.tracking)
                .foregroundStyle(.accent.opacity(0.54))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    let workout = Workout(
        name: "Morning Climb",
        date: Date(timeIntervalSince1970: 1_711_581_200),
        duration: 2_027,
        steps: 2_502,
        floors: 156,
        stepsPerFloor: 16,
        avgHeartRate: 145,
        caloriesBurned: 511
    )

    let composition = WorkoutShareCardComposer().compose(
        workout: workout,
        measurementSystem: .imperial,
        stepHeight: 8,
        preferredMetric: .steps
    )

    return WorkoutSquareShareCard(composition: composition)
        .frame(
            width: WorkoutShareCarouselViewModel.displayCardWidth,
            height: WorkoutShareCarouselViewModel.displayCardHeight
        )
        .padding()
        .background(.black)
}
