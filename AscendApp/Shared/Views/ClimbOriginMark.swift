import SwiftUI

/// The small glyph on a leaderboard row that says how the climbs behind it were recorded: on the
/// headphones, imported from Apple Health, or typed in by hand.
///
/// Quiet on purpose. It is provenance, not a badge: a row earns its place by climbing, and the
/// mark only lets the reader weigh a typed total against a measured one. Never lime - lime means
/// earned.
struct ClimbOriginMark: View {
    let origin: ClimbOrigin
    var pointSize: CGFloat = 11
    var tint: Color = .white.opacity(0.5)

    var body: some View {
        Image(systemName: origin.symbolName)
            .font(.system(size: pointSize, weight: .semibold))
            .foregroundStyle(tint)
            .accessibilityLabel(origin.accessibilityLabel)
    }
}

extension ClimbOrigin {
    /// SF Symbols, per the project's icon rule.
    var symbolName: String {
        switch self {
        case .live:
            return "headphones"
        case .healthImport:
            return "heart.fill"
        case .manual:
            return "pencil"
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(ClimbOrigin.allCases, id: \.self) { origin in
            ClimbOriginMark(origin: origin)
        }
    }
    .padding()
    .background(.black)
}
