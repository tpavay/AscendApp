import SwiftUI

/// The two top-level views of a climber's own profile: the Overview record book
/// and the chronological Activity feed.
enum OwnProfileSegment: String, CaseIterable, Identifiable {
    case overview
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .activity: return "Activity"
        }
    }
}

/// Centered, Strava-style underline toggle that switches the profile between its
/// two segments. The segments split the width evenly; the selected one carries the
/// accent underline while the rest of the baseline stays a faint hairline.
struct ProfileSegmentToggle: View {
    @Binding var selection: OwnProfileSegment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OwnProfileSegment.allCases) { segment in
                segmentButton(segment)
            }
        }
    }

    private func segmentButton(_ segment: OwnProfileSegment) -> some View {
        let isSelected = selection == segment
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = segment
            }
        } label: {
            VStack(spacing: 9) {
                Text(segment.title)
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(isSelected ? Color.white : ProfileVisualStyle.secondaryText)

                Rectangle()
                    .fill(isSelected ? Color.ascendAccent : Color.white.opacity(0.08))
                    .frame(height: 2)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
