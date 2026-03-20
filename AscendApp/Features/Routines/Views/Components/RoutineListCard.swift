import SwiftUI

struct RoutineListCard: View {
    let routine: Routine
    var isSaved: Bool = false
    var showsBookmark: Bool = false
    var showsChevron: Bool = true
    var onBookmarkTap: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 4)

                RoutineCardSurface(
                    cornerRadius: 16,
                    darkFillOpacity: 0.18,
                    lightFillOpacity: 0.06,
                    darkStrokeOpacity: 0,
                    lightStrokeOpacity: 0
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(routine.name)
                            .font(.montserratSemiBold(size: 17))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                            .padding(.trailing, showsBookmark ? 44 : 0)

                        RoutineIntensityBarChart(
                            intervals: routine.intervals,
                            height: 44,
                            widthMode: .proportionalToDuration
                        )

                        HStack(spacing: 6) {
                            Text(metaText)
                                .font(.montserratRegular(size: 13))
                                .foregroundStyle(Color.customGray)

                            Spacer()

                            if showsChevron {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.2))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .clipShape(.rect(cornerRadius: 16))
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture {
            onTap?()
        }
        .overlay(alignment: .topTrailing) {
            if showsBookmark, let onBookmarkTap {
                BookmarkButton(isSaved: isSaved, action: onBookmarkTap)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
    }

    private var accentColor: Color {
        Color.heatMapColor(
            for: routine.averageIntensityTier.heatMapScore,
            colorScheme: colorScheme
        )
    }

    private var metaText: String {
        "\(routine.totalDurationFormatted) · \(routine.intervalCount) intervals · \(routine.levelRangeDisplay)"
    }
}

#Preview {
    VStack(spacing: 12) {
        RoutineListCard(
            routine: BuiltInRoutines.previewTemplates[6],
            showsBookmark: true,
            onBookmarkTap: {}
        )
        RoutineListCard(
            routine: BuiltInRoutines.previewTemplates[5],
            isSaved: true,
            showsBookmark: true,
            onBookmarkTap: {}
        )
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
