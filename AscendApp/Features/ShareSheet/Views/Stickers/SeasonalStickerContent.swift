import SwiftUI

/// What each seasonal sticker draws above the wordmark. Text takes the climber's Font and Color
/// through `StickerInk`; illustrations and the small accent lines keep the theme's own colours.
struct SeasonalStickerContent: View {
    let kind: SeasonalStickerKind
    let subject: ShareSheetSubject
    let ink: StickerInk
    let year: Int

    private static let amber = Color(shareHex: 0xF59E0B)
    private static let gold = Color(shareHex: 0xFBBF24)
    private static let iceBlue = Color(shareHex: 0x93C5FD)
    private static let pumpkin = Color(shareHex: 0xF97316)
    private static let checkLime = Color(shareHex: 0xA3E635)

    var body: some View {
        switch kind {
        case .turkey: turkey
        case .leaves: leaves
        case .pie: pie
        case .legDay: legDay
        case .preFeast: preFeast
        case .snowflake: snowflake
        case .cocoa: cocoa
        case .pine: pine
        case .gift: gift
        case .lights: lights
        case .newPR: newPR
        case .yearBurst: yearBurst
        case .firstClimb: firstClimb
        case .resolutions: resolutions
        case .ghostDuo: ghostDuo
        case .ghostSolo: ghostSolo
        case .spookySzn: spookySzn
        }
    }

    // MARK: November

    private var turkey: some View {
        VStack(spacing: 4) {
            SeasonalStickerArt(piece: .turkey)
            ink.text("EARNED MY TURKEY", size: 11, trackingEm: 0.04)
        }
    }

    private var leaves: some View {
        VStack(spacing: 8) {
            SeasonalStickerArt(piece: .leaves)
            VStack(spacing: 0) {
                ink.text("FALLING FOR", size: 12, lineHeight: 1.1)
                ink.text("\(subject.stepsText) STEPS", size: 12, lineHeight: 1.1)
            }
        }
    }

    private var pie: some View {
        VStack(spacing: 4) {
            SeasonalStickerArt(piece: .pie)
            ink.text("EARNED THE PIE", size: 13)
        }
    }

    private var legDay: some View {
        VStack(spacing: 4) {
            accentText("THANKFUL FOR", size: 11, trackingEm: 0.16, color: Self.amber)
            ink.text("LEG DAY", size: 30, lineHeight: 1)
        }
    }

    private var preFeast: some View {
        SeasonalStickerFrame(accent: Self.amber) {
            VStack(spacing: 4) {
                accentText("PRE-FEAST", size: 9, trackingEm: 0.16, color: Self.amber)
                ink.text(subject.stepsText, size: 22, lineHeight: 1)
                ink.text("STEPS BANKED", size: 9, trackingEm: 0.16)
            }
        }
    }

    // MARK: December

    private var snowflake: some View {
        VStack(spacing: 6) {
            SeasonalStickerArt(piece: .snowflake)
            ink.text("SLEIGHED IT", size: 20, lineHeight: 1)
            accentText(
                "\(subject.stepsText) STEPS \u{00B7} \(subject.durationText)",
                size: 8,
                trackingEm: 0.16,
                color: Self.iceBlue
            )
        }
    }

    private var cocoa: some View {
        VStack(spacing: 4) {
            SeasonalStickerArt(piece: .mug)
            ink.text("COCOA EARNED", size: 12)
        }
    }

    private var pine: some View {
        VStack(spacing: 4) {
            SeasonalStickerArt(piece: .pine)
            ink.text("TREE-MENDOUS", size: 11, trackingEm: 0.04)
        }
    }

    private var gift: some View {
        SeasonalStickerArt(piece: .gift)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ink.text("GIFT OF", size: 13, lineHeight: 1)
                    ink.text("GAINS", size: 13, lineHeight: 1)
                }
                .padding(8)
            }
    }

    private var lights: some View {
        VStack(spacing: 6) {
            SeasonalStickerArt(piece: .lights)
            ink.text("MERRY & BRIGHT", size: 14)
        }
    }

    // MARK: New Year's

    private var newPR: some View {
        SeasonalStickerFrame(accent: Self.gold) {
            VStack(spacing: 3) {
                ink.text("NEW YEAR", size: 16, lineHeight: 1)
                accentText("NEW PR", size: 26, color: Self.gold, lineHeight: 1)
            }
        }
    }

    private var yearBurst: some View {
        VStack(spacing: 2) {
            SeasonalStickerArt(piece: .burst)
            ink.text(String(year), size: 24, trackingEm: -0.03, lineHeight: 1)
        }
    }

    private var firstClimb: some View {
        VStack(spacing: 6) {
            SeasonalStickerArt(piece: .sparkles)
            VStack(spacing: 0) {
                ink.text("FIRST CLIMB", size: 12, lineHeight: 1.1)
                ink.text("OF \(String(year))", size: 12, lineHeight: 1.1)
            }
        }
    }

    private var resolutions: some View {
        VStack(alignment: .leading, spacing: 6) {
            ink.text("\(String(year)) RESOLUTIONS", size: 8, trackingEm: 0.18, opacity: 0.65)
            resolutionRow("CLIMB MORE", isChecked: true)
            resolutionRow("EVERYTHING ELSE", isChecked: false)
                .opacity(0.6)
        }
    }

    private func resolutionRow(_ title: String, isChecked: Bool) -> some View {
        HStack(spacing: 6) {
            checkbox(isChecked: isChecked)
            ink.text(title, size: 12)
        }
    }

    @ViewBuilder
    private func checkbox(isChecked: Bool) -> some View {
        if isChecked {
            RoundedRectangle(cornerRadius: 3)
                .fill(Self.checkLime)
                .frame(width: 14, height: 14)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color(shareHex: 0x0B0B0B))
                }
        } else {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(ink.color, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
    }

    // MARK: October

    private var ghostDuo: some View {
        VStack(spacing: 6) {
            SeasonalStickerArt(piece: .ghostDuo)
            ink.text("GHOSTED THE STAIRS", size: 9, trackingEm: 0.14)
        }
    }

    private var ghostSolo: some View {
        VStack(spacing: 6) {
            SeasonalStickerArt(piece: .ghostSolo)
            ink.text("\(subject.stepsText) STEPS", size: 13)
        }
    }

    private var spookySzn: some View {
        SeasonalStickerFrame(accent: Self.pumpkin) {
            VStack(spacing: 0) {
                accentText("SPOOKY", size: 18, color: Self.pumpkin, lineHeight: 1)
                ink.text("SZN", size: 18, lineHeight: 1)
                ink.text("\(subject.stepsText) \u{00B7} \(subject.durationText)", size: 8, trackingEm: 0.14)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Helpers

    /// Text in the theme's accent colour, in the climber's Font. `StickerInk.text` always paints
    /// with the climber's Color, so an accent line is built here.
    private func accentText(
        _ string: String,
        size: CGFloat,
        trackingEm: CGFloat = 0,
        color: Color,
        lineHeight: CGFloat? = nil
    ) -> some View {
        Text(string)
            .presetText(ink.font, size: size, weight: 900, trackingEm: trackingEm, color: color)
            .fixedSize()
            .frame(height: lineHeight.map { $0 * size })
    }
}
