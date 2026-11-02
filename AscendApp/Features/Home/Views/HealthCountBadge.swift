import SwiftUI

/// The red count on the Health button and the + button: workouts waiting to be imported.
struct HealthCountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.montserratBold(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Color(red: 1, green: 0.23, blue: 0.36)))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.9), lineWidth: 2))
            .accessibilityHidden(true)
    }
}
