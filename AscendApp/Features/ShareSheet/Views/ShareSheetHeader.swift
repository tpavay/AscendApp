import SwiftUI

/// Close button, `Share <climb>`, and the headline numbers. The numbers are the size of the
/// Stickers hint so the close button has room.
struct ShareSheetHeader: View {
    let subject: ShareSheetSubject
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("Share \(subject.title)")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(Color(shareHex: 0xA3A3A3))
            Text(subject.headline)
                .font(.montserratBold(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 56)
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 12)
            .padding(.top, 12)
            .accessibilityLabel("Close")
        }
    }
}
