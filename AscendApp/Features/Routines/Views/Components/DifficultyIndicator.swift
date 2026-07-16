import SwiftUI

enum RoutineDifficultyStyle {
    static func tier(for level: Int) -> IntensityTier {
        switch level {
        case 1: return .minimal
        case 2: return .light
        case 3: return .moderate
        case 4: return .high
        case 5: return .maximum
        default: return .minimal
        }
    }

    static func label(for level: Int) -> String {
        switch level {
        case 1: return "Minimal"
        case 2: return "Light"
        case 3: return "Moderate"
        case 4: return "High"
        case 5: return "Maximum"
        default: return "Unknown"
        }
    }

    static func color(for level: Int, colorScheme: ColorScheme) -> Color {
        Color.heatMapColor(
            for: tier(for: level).heatMapScore,
            colorScheme: colorScheme
        )
    }
}

struct DifficultyIndicator: View {
    let level: Int
    @Environment(\.colorScheme) private var colorScheme

    private var label: String {
        RoutineDifficultyStyle.label(for: level)
    }

    private var color: Color {
        RoutineDifficultyStyle.color(for: level, colorScheme: colorScheme)
    }

    var body: some View {
        Text(label)
            .font(.montserratMedium(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}

#Preview {
    HStack(spacing: 8) {
        DifficultyIndicator(level: 2)
        DifficultyIndicator(level: 4)
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
