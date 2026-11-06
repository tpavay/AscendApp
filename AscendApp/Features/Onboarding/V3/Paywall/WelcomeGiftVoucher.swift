import SwiftUI

/// The voucher the box gives up: the welcome price, the regular price struck through, and - only
/// while the Apple ID can still take it - the free period.
///
/// There is no countdown. The offer does not end, and a timer would only be false urgency.
struct WelcomeGiftVoucher: View {
    let offer: WelcomeGiftOffer
    let copy: WelcomeGiftCopy

    private let ink = Color.black

    var body: some View {
        VStack(spacing: 0) {
            top

            if let trialLine = copy.trialLine {
                perforation
                bottom(trialLine)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "CDF38E"), OnboardingV3Palette.accent, Color(hex: "5C9A08")],
                        startPoint: UnitPoint(x: 0.2, y: 0),
                        endPoint: UnitPoint(x: 0.8, y: 1)
                    )
                )
        )
        .shadow(color: .black.opacity(0.7), radius: 35, y: 30)
        .shadow(color: OnboardingV3Palette.accent.opacity(0.25), radius: 30)
        .overlay(alignment: .topTrailing) { stamp }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome offer")
                .paywallText(.black, size: 12, tracking: 0.2, relativeTo: .caption)
                .textCase(.uppercase)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                // The stamp reaches 44 points into this column, and a label running under it loses
                // its last letters. 12 more keeps it clear at every text size.
                .padding(.trailing, copy.stamp == nil ? 0 : 56)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(offer.price)
                    .paywallText(.black, size: 76, tracking: -0.04, relativeTo: .largeTitle)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)

                Text("/year")
                    .paywallText(.extraBold, size: 18, relativeTo: .headline)
            }

            (Text(offer.regularPrice).strikethrough() + Text(" · your price, every year"))
                .paywallText(.bold, size: 15, relativeTo: .subheadline)
                .foregroundStyle(ink.opacity(0.6))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var perforation: some View {
        ZStack {
            Rectangle()
                .stroke(ink.opacity(0.25), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                .frame(height: 0)
                .padding(.horizontal, 18)

            HStack {
                Circle().fill(Color.black).frame(width: 30, height: 30).offset(x: -15)
                Spacer()
                Circle().fill(Color.black).frame(width: 30, height: 30).offset(x: 15)
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }

    private func bottom(_ trialLine: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trialLine.prefix(while: { $0 != " " }))
                .paywallText(.extraBold, size: 12, tracking: 0.14, relativeTo: .caption)
                .foregroundStyle(ink.opacity(0.6))

            Text(trialLine.drop(while: { $0 != " " }).dropFirst())
                .paywallText(.black, size: 22, relativeTo: .title3)
                .foregroundStyle(ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stamp: some View {
        if let percent = copy.stamp {
            VStack(spacing: 0) {
                Text(percent)
                    .paywallText(.black, size: 24, relativeTo: .title2)
                Text("OFF")
                    .paywallText(.black, size: 12, tracking: 0.1, relativeTo: .caption)
            }
            // The circle stays this size at every text size, so the figure shrinks to fit it.
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .padding(10)
            .foregroundStyle(OnboardingV3Palette.accent)
            .frame(width: 78, height: 78)
            .background(Color(hex: "0A0A0A"), in: Circle())
            .shadow(color: .black.opacity(0.4), radius: 10, y: 8)
            .rotationEffect(.degrees(-12))
            .offset(x: 12, y: -30)
            .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Welcome offer", "\(offer.price) a year", "regular price \(offer.regularPrice)"]
        if let stamp = copy.stamp { parts.append("\(stamp) off") }
        if let trialLine = copy.trialLine { parts.append(trialLine.capitalized) }
        return parts.joined(separator: ", ")
    }
}
