import SwiftUI

struct TopProgressBar: View {
    let elapsed: String
    let remaining: String
    let progress: Double

    var body: some View {
        HStack(spacing: 12) {
            // Elapsed time
            Text(elapsed)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 50, alignment: .leading)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.2))
                        .frame(height: 8)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.accent)
                        .frame(width: geometry.size.width * min(1, max(0, progress)), height: 8)
                        .animation(.linear(duration: 0.1), value: progress)
                }
            }
            .frame(height: 8)

            // Remaining time
            Text(remaining)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.96))
    }
}

#Preview {
    ZStack {
        Color.jet.ignoresSafeArea()
        VStack {
            TopProgressBar(elapsed: "5:32", remaining: "14:28", progress: 0.28)
            Spacer()
        }
    }
}
