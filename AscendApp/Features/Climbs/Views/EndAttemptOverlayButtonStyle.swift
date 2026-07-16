import SwiftUI

enum EndAttemptOverlayButtonStyle {
    case primary
    case secondary
    case destructive

    var foregroundStyle: Color {
        switch self {
        case .primary:
            return .black
        case .secondary:
            return .white
        case .destructive:
            return Color.red.opacity(0.96)
        }
    }

    var backgroundStyle: Color {
        switch self {
        case .primary:
            return Color.accent
        case .secondary:
            return .white.opacity(0.10)
        case .destructive:
            return .white.opacity(0.07)
        }
    }
}
