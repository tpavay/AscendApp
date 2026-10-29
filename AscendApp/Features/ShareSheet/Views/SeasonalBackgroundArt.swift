import SwiftUI

/// The illustration behind a seasonal card, filling its 310 by 310 design space. The art is a
/// bundled 1080 pixel square with no text; the only part drawn in code is the year on the Year
/// card, because the year changes and a baked image would be wrong every January after the first.
struct SeasonalBackgroundArt: View {
    let background: SeasonalBackground
    var year: Int = Calendar.current.component(.year, from: .now)

    var body: some View {
        let side = PresetCardView.designSize
        // The image is an overlay on `Color.clear` so a fill can never widen the view that holds it.
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                Image(decorative: assetName)
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                if background == .yearGold {
                    SeasonalOutlinedYear(year: year)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var assetName: String {
        switch background {
        case .leafFall: return "Seasonal/LeafFall"
        case .flannel: return "Seasonal/Flannel"
        case .snowfall: return "Seasonal/Snowfall"
        case .snowyPines: return "Seasonal/SnowyPines"
        case .twinkleLights: return "Seasonal/TwinkleLights"
        case .giftWrap: return "Seasonal/GiftWrap"
        case .cocoa: return "Seasonal/Cocoa"
        case .fireworks: return "Seasonal/Fireworks"
        case .confetti: return "Seasonal/Confetti"
        case .yearGold: return "Seasonal/YearGold"
        case .bubblyGold: return "Seasonal/BubblyGold"
        case .ghosts: return "Seasonal/Ghosts"
        }
    }
}
