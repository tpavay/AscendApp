#if DEBUG
import SwiftUI

struct JourneyRouteMarker: View {
    let step: JourneyStep
    let accent: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: isSelected ? 34 : 28, height: isSelected ? 34 : 28)
                .shadow(color: shadowColor, radius: isSelected ? 12 : 6, x: 0, y: 2)

            markerContent
        }
        .overlay {
            Circle()
                .strokeBorder(borderColor, lineWidth: isSelected ? 3 : 2)
                .frame(width: isSelected ? 34 : 28, height: isSelected ? 34 : 28)
        }
    }

    @ViewBuilder
    private var markerContent: some View {
        switch step.status {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.black)
        case .current:
            Text("\(step.index + 1)")
                .font(.montserratBold(size: 12))
                .foregroundStyle(.black)
        case .locked:
            Text("\(step.index + 1)")
                .font(.montserratBold(size: 11))
                .foregroundStyle(.white.opacity(0.68))
        }
    }

    private var fillColor: Color {
        switch step.status {
        case .completed, .current:
            accent
        case .locked:
            .black.opacity(0.78)
        }
    }

    private var borderColor: Color {
        switch step.status {
        case .completed:
            .white.opacity(0.92)
        case .current:
            .white
        case .locked:
            .white.opacity(0.38)
        }
    }

    private var shadowColor: Color {
        switch step.status {
        case .completed, .current:
            accent.opacity(0.5)
        case .locked:
            .black.opacity(0.35)
        }
    }
}
#endif
