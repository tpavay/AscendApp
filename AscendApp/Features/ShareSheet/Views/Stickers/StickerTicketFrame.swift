import SwiftUI

/// The ticket outline shared by the Ticket and Yearly rank stickers: a rounded border, a tracked
/// header, a dashed rule, then the body.
struct StickerTicketFrame<Inner: View>: View {
    let ink: StickerInk
    let header: String
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minWidth: CGFloat?
    private let ticketBody: Inner

    init(
        ink: StickerInk,
        header: String,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        minWidth: CGFloat?,
        @ViewBuilder ticketBody: () -> Inner
    ) {
        self.ink = ink
        self.header = header
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.minWidth = minWidth
        self.ticketBody = ticketBody()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ink.caption(header, trackingEm: 0.16, opacity: 1)
                Spacer(minLength: 0)
            }
            DashedRule()
                .stroke(ink.color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 1.5)
                .opacity(0.6)
            ticketBody
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(minWidth: minWidth, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 9).strokeBorder(ink.color, lineWidth: 1.5)
        }
    }

    private struct DashedRule: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
