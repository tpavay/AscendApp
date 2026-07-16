import SwiftUI

struct LiveSessionTimelineView<Bar: View>: View {
    let title: String?
    let elapsedLabel: String
    let totalLabel: String
    let barHeight: CGFloat
    let bar: () -> Bar

    init(
        title: String? = nil,
        elapsedLabel: String,
        totalLabel: String,
        barHeight: CGFloat,
        @ViewBuilder bar: @escaping () -> Bar
    ) {
        self.title = title
        self.elapsedLabel = elapsedLabel
        self.totalLabel = totalLabel
        self.barHeight = barHeight
        self.bar = bar
    }

    var body: some View {
        VStack(spacing: 7) {
            if let title {
                Text(title)
                    .font(.montserratMedium(size: 12))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.22))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)
            }

            HStack {
                Text(elapsedLabel)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(totalLabel)
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.28))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .monospacedDigit()

            bar()
                .frame(height: barHeight)
        }
    }
}

struct LiveSessionLinearProgressBar: View {
    let progress: Double
    var fill: Color = .accent
    var trackOpacity: Double = 0.08

    var body: some View {
        GeometryReader { geometry in
            Capsule(style: .continuous)
                .fill(.white.opacity(trackOpacity))
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(fill)
                        .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
                        .shadow(color: fill.opacity(0.24), radius: 5)
                }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        LiveSessionTimelineView(
            title: "Pyramid Climb",
            elapsedLabel: "0:05",
            totalLabel: "20:00",
            barHeight: 2
        ) {
            LiveSessionLinearProgressBar(progress: 0.34)
        }
        .padding(24)
    }
}
