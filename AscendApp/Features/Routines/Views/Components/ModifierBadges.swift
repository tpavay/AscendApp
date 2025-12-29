import SwiftUI

struct ModifierBadges: View {
    let modifiers: IntervalModifiers

    var body: some View {
        if modifiers.hasAnyActive {
            HStack(spacing: 8) {
                ForEach(modifiers.activeModifiers, id: \.self) { modifier in
                    ModifierBadge(text: modifier)
                }
            }
        }
    }
}

struct ModifierBadge: View {
    let text: String

    private var icon: String? {
        switch text {
        case "Facing Left":
            return "arrow.left"
        case "Facing Right":
            return "arrow.right"
        case "Skip Step":
            return "arrow.up.to.line"
        case "Backward":
            return "arrow.uturn.backward"
        case "Holding Bars":
            return "hand.raised"
        default:
            return "star"
        }
    }

    private var iconTrailing: Bool {
        text == "Facing Right"
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon, !iconTrailing {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(text)
                .font(.montserratMedium(size: 13))
            if let icon = icon, iconTrailing {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.accent.opacity(0.15))
        )
    }
}

#Preview {
    ZStack {
        Color.jet.ignoresSafeArea()
        VStack(spacing: 20) {
            ModifierBadges(modifiers: IntervalModifiers(sidewaysDirection: .left, holdingBars: true))
            ModifierBadges(modifiers: IntervalModifiers(sidewaysDirection: .right))
            ModifierBadges(modifiers: IntervalModifiers(skipStep: true))
            ModifierBadges(modifiers: IntervalModifiers())
        }
    }
}
