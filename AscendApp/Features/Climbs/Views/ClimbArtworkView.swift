import SwiftUI

struct ClimbArtworkView: View {
    let climb: Climb
    let variant: ClimbImageVariant
    private let imageRepository: any ClimbImageRepository

    @State private var resolvedURL: URL?
    @State private var isLoading = false

    init(
        climb: Climb,
        variant: ClimbImageVariant,
        imageRepository: any ClimbImageRepository = FirebaseClimbImageRepository.shared
    ) {
        self.climb = climb
        self.variant = variant
        self.imageRepository = imageRepository
    }

    var body: some View {
        ZStack {
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            if isLoading {
                ProgressView()
                    .tint(.white.opacity(0.85))
                    .scaleEffect(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: taskKey) {
            await resolveArtwork()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    climb.tier.color.opacity(0.65),
                    Color.night,
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            placeholderContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var placeholderContent: some View {
        if variant == .hero {
            VStack(spacing: 10) {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))

                Text(climb.name)
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .padding(24)
        } else {
            Image(systemName: placeholderSymbol)
                .font(.system(size: variant == .card ? 22 : 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var taskKey: String {
        "\(climb.id)-\(variant.rawValue)-v\(climb.imageSetVersion)"
    }

    private var placeholderSymbol: String {
        switch climb.category {
        case "mountain":
            return "mountain.2.fill"
        case "bridge":
            return "point.topleft.down.curvedto.point.bottomright.up.fill"
        case "pyramid":
            return "triangle.fill"
        case "stadium":
            return "sportscourt.fill"
        default:
            return "building.2.fill"
        }
    }

    @MainActor
    private func resolveArtwork() async {
        isLoading = true
        let url = await imageRepository.resolveImageURL(for: climb, variant: variant)

        guard !Task.isCancelled else { return }

        resolvedURL = url
        isLoading = false
    }
}
