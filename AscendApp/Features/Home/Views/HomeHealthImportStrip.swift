import SwiftUI

/// "Imported from Apple Health": the receipt for an automatic import, shown the next time Home
/// appears. Edit opens the quick edit sheet; the strip retires when it is used or after a day.
struct HomeHealthImportStrip: View {
    let notice: AppleHealthImportService.HomeNotice
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accent))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Imported from Apple Health")
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button(action: onEdit) {
                Text("Edit")
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(Color.accent)
                    .padding(.vertical, 10)
                    .padding(.leading, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.28), lineWidth: 1)
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.7))
        )
    }

    /// `Today · 4,912 steps · 1:02:50`, with `Add steps` where Health recorded none.
    private var detail: String {
        let day = Calendar.current.isDateInToday(notice.startDate)
            ? "Today"
            : notice.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day) · \(ImportsRowFormat.stepsText(notice.steps)) · \(ImportsRowFormat.durationText(notice.duration))"
    }
}
