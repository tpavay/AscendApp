import SwiftUI

struct RoutineThumbnailCard: View {
    let routine: Routine
    var width: CGFloat = 168
    var height: CGFloat = 110
    var accentBarWidth: CGFloat = 3
    var cornerRadius: CGFloat = 14
    var chartHeight: CGFloat = 36
    var titleLineLimit: Int = 2
    var widthMode: RoutineIntensityBarChartWidthMode = .equalSegments
    var showsLevelRange: Bool = false
    var isSaved: Bool = false
    var showsBookmark: Bool = false
    var onBookmarkTap: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var contentWidth: CGFloat {
        max(width - accentBarWidth, 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            LeadingAccentStripe(
                color: accentColor,
                width: accentBarWidth,
                cornerRadius: cornerRadius
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(routine.name)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(titleLineLimit)
                    .padding(.trailing, showsBookmark ? 44 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)

                RoutineIntensityBarChart(
                    intervals: routine.intervals,
                    height: chartHeight,
                    widthMode: widthMode
                )

                Text(metaText)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(Color.customGray)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(width: contentWidth, height: height, alignment: .topLeading)
            .background(cardBackground)
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .contentShape(.rect(cornerRadius: cornerRadius))
        .onTapGesture {
            onTap?()
        }
        .overlay(alignment: .topTrailing) {
            if showsBookmark, let onBookmarkTap {
                BookmarkButton(isSaved: isSaved, action: onBookmarkTap)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
    }

    private var metaText: String {
        if showsLevelRange {
            return "\(routine.totalDurationFormatted) · \(routine.intervalCount) intervals · \(routine.levelRangeDisplay)"
        }
        return "\(routine.totalDurationFormatted) · \(routine.intervalCount) intervals"
    }

    private var accentColor: Color {
        RoutineIntervalScale.averageColor(of: routine.intervals, colorScheme: colorScheme)
    }

    private var cardBackground: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.35) : .gray.opacity(0.08)
    }
}

#Preview {
    HStack(spacing: 12) {
        RoutineThumbnailCard(routine: BuiltInRoutines.previewTemplates[0])
        RoutineThumbnailCard(routine: BuiltInRoutines.previewTemplates[4])
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
