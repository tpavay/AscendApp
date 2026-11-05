import SwiftUI

/// 05 Climb with what you've got: the three ways a climb gets counted. They are information, not
/// choices - nothing here is tappable but Continue - because every one of them works.
struct OnboardingCountMethodsScreen: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: .countMethods)
                .padding(.top, 9)

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            OnboardingHeadline(
                                SellScreenCopy.CountMethods.headlineLead,
                                accentLines: SellScreenCopy.CountMethods.headlineAccent
                            )

                            Text(SellScreenCopy.CountMethods.body)
                                .onboardingSecondary()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 14) {
                            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                                SellMethodRow(method: row.method, symbol: row.symbol, tile: row.tile)
                                    .onboardingEntrance(delay: 0.1 + 0.12 * Double(index), duration: 0.45)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }

            Button(SellScreenCopy.continueTitle, action: coordinator.advance)
                .buttonStyle(.onboardingPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .trackOnce(screen: .onboardingCountMethods)
    }

    private struct Row {
        let method: SellScreenCopy.CountMethods.Method
        let symbol: String
        let tile: [Color]
    }

    private static let rows: [Row] = [
        Row(
            method: SellScreenCopy.CountMethods.methods[0],
            symbol: "headphones",
            tile: [Color(hex: "E8FFC2"), OnboardingV3Palette.accent]
        ),
        Row(
            method: SellScreenCopy.CountMethods.methods[1],
            symbol: "heart",
            tile: [Color(hex: "FFD6DE"), Color(hex: "FF6B85")]
        ),
        Row(
            method: SellScreenCopy.CountMethods.methods[2],
            symbol: "keyboard",
            tile: [Color(hex: "FFE8C8"), OnboardingV3Palette.orange]
        )
    ]
}

private struct SellMethodRow: View {
    let method: SellScreenCopy.CountMethods.Method
    let symbol: String
    let tile: [Color]

    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var detailSize: CGFloat = 13
    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 60

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: tile, startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                        .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
                }
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: tileSize * 0.48, weight: .semibold))
                        .foregroundStyle(Color.black)
                }
                .frame(width: tileSize, height: tileSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(method.title)
                        .font(.custom("Montserrat-ExtraBold", fixedSize: titleSize))
                        .foregroundStyle(Color.white)

                    if method.isBest {
                        Text(SellScreenCopy.CountMethods.bestBadge)
                            .textCase(.uppercase)
                            .font(.custom("Montserrat-Black", fixedSize: 10))
                            .tracking(1.2)
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OnboardingV3Palette.accent))
                    }
                }

                Text(method.detail)
                    .font(.custom("Montserrat-Medium", fixedSize: detailSize))
                    .foregroundStyle(OnboardingV3Palette.secondary)
                    .lineSpacing(detailSize * 0.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .onboardingCard(cornerRadius: 22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(method.isBest ? Color(hex: "2E4415") : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(method.isBest ? "\(method.title), best. \(method.detail)" : "\(method.title). \(method.detail)")
    }
}
