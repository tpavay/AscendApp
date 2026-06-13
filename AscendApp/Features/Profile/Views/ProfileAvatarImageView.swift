import SwiftUI

struct ProfileAvatarImageView: View {
    let photoURL: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: photoURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: size * 0.62, weight: .semibold))
                            .foregroundStyle(Color.ascendAccent)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.ascendAccent.opacity(0.86), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}
