import SwiftUI

struct OnboardingLeaderboardValuePageContent: View {
    let headline: String
    let subtitle: String

    private let rows: [OnboardingLeaderboardValueRow] = [
        OnboardingLeaderboardValueRow(
            rank: "30",
            name: "Ava M.",
            detail: "Woman · 29 · Denver, CO",
            score: "106",
            avatarImageName: "OnboardingLeaderboardAvatarAva"
        ),
        OnboardingLeaderboardValueRow(
            rank: "31",
            name: "Noah R.",
            detail: "Man · 34 · Austin, TX",
            score: "103",
            avatarImageName: "OnboardingLeaderboardAvatarNoah"
        ),
        OnboardingLeaderboardValueRow(
            rank: "32",
            name: "Maya D.",
            detail: "Woman · 27 · Sydney, AU",
            score: "102",
            avatarImageName: "OnboardingLeaderboardAvatarMaya"
        ),
        OnboardingLeaderboardValueRow(
            rank: "33",
            name: "Miles K.",
            detail: "Man · 41 · Portland, OR",
            score: "98",
            avatarImageName: "OnboardingLeaderboardAvatarMiles"
        ),
        OnboardingLeaderboardValueRow(
            rank: "34",
            name: "You",
            detail: "Man · 31 · Denver, CO",
            score: "89",
            avatarImageName: nil,
            isCurrentUser: true
        ),
        OnboardingLeaderboardValueRow(
            rank: "35",
            name: "Ethan P.",
            detail: "Man · 26 · Milan, IT",
            score: "85",
            avatarImageName: "OnboardingLeaderboardAvatarEthan"
        )
    ]

    var body: some View {
        GeometryReader { geometry in
            let layout = OnboardingLeaderboardValueLayout(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets
            )

            ZStack(alignment: .topLeading) {
                Color.black
                    .ignoresSafeArea()

                leaderboardBackground(layout: layout)

                leaderboardGlow(layout: layout)

                OnboardingLeaderboardHeader(layout: layout)
                    .offset(x: layout.contentLeft, y: layout.headerTop)

                Rectangle()
                    .fill(.white.opacity(0.13))
                    .frame(width: layout.contentWidth, height: 1)
                    .offset(x: layout.contentLeft, y: layout.dividerTop)

                leaderboardRows(layout: layout)
                    .offset(x: layout.contentLeft, y: layout.rowsTop)

                textContent(layout: layout)
                    .padding(.horizontal, layout.sharedLayout.horizontalPadding)
                    .frame(height: layout.sharedLayout.textSectionHeight, alignment: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, layout.sharedLayout.textSectionBottomPadding)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline.replacingOccurrences(of: "\n", with: " ")) \(subtitle)")
    }

    private func leaderboardBackground(layout: OnboardingLeaderboardValueLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Image("OnboardingLeaderboardsBackground")
                .resizable()
                .frame(
                    width: layout.backgroundImageSize.width,
                    height: layout.backgroundImageSize.height
                )
                .offset(x: layout.backgroundImageLeft, y: layout.backgroundImageTop)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func leaderboardGlow(layout: OnboardingLeaderboardValueLayout) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        OnboardingValuePalette.lime.opacity(0.14),
                        OnboardingValuePalette.lime.opacity(0.05),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: layout.glowSize.width * 0.48
                )
            )
            .frame(width: layout.glowSize.width, height: layout.glowSize.height)
            .blur(radius: layout.glowBlur)
            .offset(x: layout.glowLeft, y: layout.glowTop)
            .allowsHitTesting(false)
    }

    private func leaderboardRows(layout: OnboardingLeaderboardValueLayout) -> some View {
        VStack(spacing: layout.rowGap) {
            ForEach(rows) { row in
                OnboardingLeaderboardRowView(row: row, layout: layout)
            }
        }
        .frame(width: layout.contentWidth, alignment: .topLeading)
    }

    private func textContent(layout: OnboardingLeaderboardValueLayout) -> some View {
        VStack(spacing: 0) {
            styledHeadline
                .font(.montserratBold(size: layout.sharedLayout.headlineSize))
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: layout.textWidth)

            Text(subtitle)
                .font(.montserratRegular(size: layout.sharedLayout.subtitleSize))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: layout.subtitleWidth)
                .padding(.top, layout.sharedLayout.textStackSpacing)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var styledHeadline: Text {
        Text("See where\nyou ")
            .foregroundStyle(.white)
        + Text("stand.")
            .foregroundStyle(OnboardingValuePalette.lime)
    }
}

private struct OnboardingLeaderboardHeader: View {
    let layout: OnboardingLeaderboardValueLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("OnboardingLeaderboardEmpireThumbnail")
                .resizable()
                .scaledToFill()
                .frame(width: layout.headerThumbnailSize, height: layout.headerThumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: layout.headerThumbnailCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: layout.headerThumbnailCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
                .offset(x: layout.headerThumbnailLeft, y: layout.headerThumbnailTop)

            VStack(alignment: .leading, spacing: 0) {
                Text("LIVE CLIMB")
                    .font(.montserratBold(size: layout.headerEyebrowFontSize))
                    .tracking(0.9 * layout.typeScale)
                    .foregroundStyle(OnboardingValuePalette.lime)
                    .lineLimit(1)
                    .frame(height: layout.scaledY(13), alignment: .center)

                Text("Empire State\nBuilding")
                    .font(.montserratBold(size: layout.headerTitleFontSize))
                    .foregroundStyle(.white)
                    .lineSpacing(0)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: layout.scaledY(32), alignment: .center)
                    .padding(.top, layout.scaledY(2))

                Text("New York, USA")
                    .font(.montserratMedium(size: layout.headerLocationFontSize))
                    .foregroundStyle(Color(red: 158 / 255, green: 158 / 255, blue: 158 / 255))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: layout.scaledY(15), alignment: .center)
                    .padding(.top, layout.scaledY(1))
            }
            .frame(width: layout.scaledX(150), alignment: .leading)
            .offset(x: layout.headerTextLeft, y: layout.headerTextTop)

            ZStack {
                RoundedRectangle(cornerRadius: layout.timerCornerRadius, style: .continuous)
                    .fill(Color(red: 27 / 255, green: 27 / 255, blue: 27 / 255))
                    .overlay {
                        RoundedRectangle(cornerRadius: layout.timerCornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }

                Text("0:58")
                    .font(.montserratBold(size: layout.timerFontSize))
                    .foregroundStyle(.white)
            }
            .frame(width: layout.timerWidth, height: layout.timerHeight)
            .offset(x: layout.timerLeft, y: layout.timerTop)

            Text("LEADERBOARD")
                .font(.montserratBold(size: layout.leaderboardLabelFontSize))
                .tracking(1.05 * layout.typeScale)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: layout.scaledX(170), height: layout.scaledY(18), alignment: .leading)
                .offset(x: 0, y: layout.leaderboardLabelTop)

            HStack(alignment: .lastTextBaseline, spacing: layout.scaledX(5)) {
                Text("2,096")
                    .font(.montserratBold(size: layout.stepsValueFontSize))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("STEPS")
                    .font(.montserratBold(size: layout.stepsLabelFontSize))
                    .tracking(0.45 * layout.typeScale)
                    .foregroundStyle(Color(red: 92 / 255, green: 92 / 255, blue: 92 / 255))
                    .lineLimit(1)
            }
            .frame(width: layout.scaledX(108), height: layout.scaledY(26), alignment: .trailing)
            .offset(x: layout.contentWidth - layout.scaledX(108), y: layout.stepsLockupTop)
        }
        .frame(width: layout.contentWidth, height: layout.headerHeight, alignment: .topLeading)
    }
}

private struct OnboardingLeaderboardRowView: View {
    let row: OnboardingLeaderboardValueRow
    let layout: OnboardingLeaderboardValueLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            if row.isCurrentUser {
                RoundedRectangle(cornerRadius: layout.activeRowCornerRadius, style: .continuous)
                    .fill(Color(red: 11 / 255, green: 27 / 255, blue: 0).opacity(0.97))
                    .overlay {
                        RoundedRectangle(cornerRadius: layout.activeRowCornerRadius, style: .continuous)
                            .strokeBorder(OnboardingValuePalette.lime.opacity(0.58), lineWidth: 1)
                    }
                    .frame(width: layout.contentWidth, height: layout.activeRowHeight)
                    .offset(y: layout.activeRowTopOffset)
            }

            Text(row.rank)
                .font(.montserratBold(size: layout.rankFontSize))
                .foregroundStyle(row.isCurrentUser ? OnboardingValuePalette.lime : Color(red: 92 / 255, green: 92 / 255, blue: 92 / 255))
                .lineLimit(1)
                .frame(width: layout.rankWidth, height: layout.rankHeight, alignment: .center)
                .offset(x: layout.rankLeft, y: layout.rankTop)

            avatar
                .frame(width: layout.avatarSize, height: layout.avatarSize)
                .offset(x: layout.avatarLeft, y: layout.avatarTop)

            VStack(alignment: .leading, spacing: layout.detailTopGap) {
                Text(row.name)
                    .font(.montserratBold(size: layout.rowNameFontSize))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(row.detail)
                    .font(.montserratMedium(size: layout.rowDetailFontSize))
                    .foregroundStyle(row.isCurrentUser ? .white.opacity(0.82) : Color(red: 158 / 255, green: 158 / 255, blue: 158 / 255).opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .frame(width: layout.rowTextWidth, alignment: .leading)
            .offset(x: layout.rowTextLeft, y: layout.rowTextTop)

            Text(row.score)
                .font(.montserratBold(size: layout.scoreFontSize))
                .foregroundStyle(row.isCurrentUser ? OnboardingValuePalette.lime : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: layout.scoreWidth, height: layout.scoreHeight, alignment: .trailing)
                .offset(x: layout.scoreLeft, y: layout.scoreTop)
        }
        .frame(width: layout.contentWidth, height: layout.rowHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private var avatar: some View {
        if row.isCurrentUser {
            ZStack {
                Circle()
                    .fill(OnboardingValuePalette.lime)

                Text("YOU")
                    .font(.montserratBold(size: layout.userAvatarFontSize))
                    .foregroundStyle(.black)
                    .lineLimit(1)
            }
        } else if let avatarImageName = row.avatarImageName {
            Image(avatarImageName)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        }
    }
}

private struct OnboardingLeaderboardValueRow: Identifiable {
    let rank: String
    let name: String
    let detail: String
    let score: String
    let avatarImageName: String?
    var isCurrentUser = false

    var id: String { rank }
}

private enum OnboardingLeaderboardValueTuning {
    // Adjust this value in Xcode previews to move the streak background crop up/down.
    static let backgroundTopOffset: CGFloat = -120
}

private struct OnboardingLeaderboardValueLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var sharedLayout: OnboardingValueShowcaseLayout {
        OnboardingValueShowcaseLayout(
            size: size,
            safeAreaInsets: safeAreaInsets
        )
    }

    var scaleX: CGFloat {
        size.width / 390
    }

    var scaleY: CGFloat {
        size.height / 844
    }

    var typeScale: CGFloat {
        min(scaleX, scaleY)
    }

    func scaledX(_ value: CGFloat) -> CGFloat {
        value * scaleX
    }

    func scaledY(_ value: CGFloat) -> CGFloat {
        value * scaleY
    }

    var contentLeft: CGFloat {
        scaledX(27)
    }

    var contentWidth: CGFloat {
        min(scaledX(334), size.width - (contentLeft * 2))
    }

    var backgroundImageLeft: CGFloat {
        scaledX(-527)
    }

    var backgroundImageTop: CGFloat {
        scaledY(OnboardingLeaderboardValueTuning.backgroundTopOffset)
    }

    var backgroundImageSize: CGSize {
        CGSize(width: scaledX(1402), height: scaledY(1122))
    }

    var leaderboardDownShift: CGFloat {
        scaledY(24)
    }

    var headerTop: CGFloat {
        scaledY(111) + leaderboardDownShift
    }

    var headerHeight: CGFloat {
        scaledY(92)
    }

    var dividerTop: CGFloat {
        scaledY(206) + leaderboardDownShift
    }

    var rowsTop: CGFloat {
        scaledY(223) + leaderboardDownShift
    }

    var rowHeight: CGFloat {
        scaledY(43)
    }

    var rowGap: CGFloat {
        scaledY(4)
    }

    var glowSize: CGSize {
        CGSize(width: scaledX(294), height: scaledY(210))
    }

    var glowLeft: CGFloat {
        scaledX(47)
    }

    var glowTop: CGFloat {
        scaledY(321) + leaderboardDownShift
    }

    var glowBlur: CGFloat {
        22 * typeScale
    }

    var textWidth: CGFloat {
        min(334, size.width - sharedLayout.horizontalPadding * 2)
    }

    var subtitleWidth: CGFloat {
        min(314, size.width - sharedLayout.horizontalPadding * 2)
    }

    var headerThumbnailLeft: CGFloat {
        scaledX(18)
    }

    var headerThumbnailTop: CGFloat {
        scaledY(1)
    }

    var headerThumbnailSize: CGFloat {
        scaledX(62)
    }

    var headerThumbnailCornerRadius: CGFloat {
        scaledX(13)
    }

    var headerTextLeft: CGFloat {
        scaledX(94)
    }

    var headerTextTop: CGFloat {
        scaledY(1)
    }

    var headerEyebrowFontSize: CGFloat {
        8.3 * typeScale
    }

    var headerTitleFontSize: CGFloat {
        12.8 * typeScale
    }

    var headerLocationFontSize: CGFloat {
        10.2 * typeScale
    }

    var timerLeft: CGFloat {
        contentWidth - timerWidth
    }

    var timerTop: CGFloat {
        scaledY(10)
    }

    var timerWidth: CGFloat {
        scaledX(52)
    }

    var timerHeight: CGFloat {
        scaledY(38)
    }

    var timerCornerRadius: CGFloat {
        scaledX(10)
    }

    var timerFontSize: CGFloat {
        13.8 * typeScale
    }

    var leaderboardLabelTop: CGFloat {
        scaledY(74)
    }

    var leaderboardLabelFontSize: CGFloat {
        14.2 * typeScale
    }

    var stepsLockupTop: CGFloat {
        scaledY(64)
    }

    var stepsValueFontSize: CGFloat {
        20 * typeScale
    }

    var stepsLabelFontSize: CGFloat {
        9 * typeScale
    }

    var activeRowHeight: CGFloat {
        scaledY(47)
    }

    var activeRowTopOffset: CGFloat {
        scaledY(-2)
    }

    var activeRowCornerRadius: CGFloat {
        scaledX(8)
    }

    var rankLeft: CGFloat {
        scaledX(4)
    }

    var rankTop: CGFloat {
        scaledY(10)
    }

    var rankWidth: CGFloat {
        scaledX(34)
    }

    var rankHeight: CGFloat {
        scaledY(22)
    }

    var rankFontSize: CGFloat {
        15 * typeScale
    }

    var avatarLeft: CGFloat {
        scaledX(56)
    }

    var avatarTop: CGFloat {
        scaledY(5)
    }

    var avatarSize: CGFloat {
        scaledX(34)
    }

    var userAvatarFontSize: CGFloat {
        7.4 * typeScale
    }

    var rowTextLeft: CGFloat {
        scaledX(106)
    }

    var rowTextTop: CGFloat {
        scaledY(5)
    }

    var rowTextWidth: CGFloat {
        scaledX(180)
    }

    var detailTopGap: CGFloat {
        scaledY(2)
    }

    var rowNameFontSize: CGFloat {
        14.7 * typeScale
    }

    var rowDetailFontSize: CGFloat {
        8.9 * typeScale
    }

    var scoreLeft: CGFloat {
        contentWidth - scoreWidth - scaledX(4)
    }

    var scoreTop: CGFloat {
        scaledY(9)
    }

    var scoreWidth: CGFloat {
        scaledX(50)
    }

    var scoreHeight: CGFloat {
        scaledY(25)
    }

    var scoreFontSize: CGFloat {
        20.5 * typeScale
    }
}

#Preview("Leaderboard Value Page") {
    OnboardingLeaderboardValuePageContent(
        headline: "See where\nyou stand.",
        subtitle: "Compete on the stair stepper. Watch your rank move in real time."
    )
}

#Preview("Leaderboard Full Screen Tuning") {
    ZStack(alignment: .topLeading) {
        OnboardingLeaderboardValuePageContent(
            headline: "See where\nyou stand.",
            subtitle: "Compete on the stair stepper. Watch your rank move in real time."
        )

        OnboardingValueShowcaseChrome(
            activePageIndex: 1,
            pageCount: 4,
            buttonTitle: "CONTINUE",
            onContinue: {}
        )

        OnboardingBackButton(isEnabled: true, action: {})
            .padding(.leading, OnboardingChromeMetrics.backButtonLeadingPadding)
            .padding(.top, OnboardingChromeMetrics.backButtonTopPadding)
    }
    .frame(width: 390, height: 844)
    .background(Color.black)
}
