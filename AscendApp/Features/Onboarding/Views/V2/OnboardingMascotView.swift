import SwiftUI
import UIKit

enum OnboardingMascotScene {
    case welcome
    case health
    case measurement
    case fitness
    case personal
    case body
    case location
    case notifications
    case auth

    var motion: MascotMotion {
        switch self {
        case .welcome:
            return MascotMotion(floatOffset: 8, tilt: -2.5, scale: 1.02, duration: 2.9)
        case .health:
            return MascotMotion(floatOffset: 6, tilt: 2, scale: 1.01, duration: 3.2)
        case .measurement:
            return MascotMotion(floatOffset: 5, tilt: -1.4, scale: 1.01, duration: 3.0)
        case .fitness:
            return MascotMotion(floatOffset: 7, tilt: 2.8, scale: 1.02, duration: 2.8)
        case .personal:
            return MascotMotion(floatOffset: 4, tilt: -1.2, scale: 1.01, duration: 3.3)
        case .body:
            return MascotMotion(floatOffset: 5, tilt: 1.4, scale: 1.02, duration: 3.1)
        case .location:
            return MascotMotion(floatOffset: 6, tilt: 2.4, scale: 1.01, duration: 2.9)
        case .notifications:
            return MascotMotion(floatOffset: 4, tilt: -2.0, scale: 1.01, duration: 3.2)
        case .auth:
            return MascotMotion(floatOffset: 3, tilt: 1.6, scale: 1.0, duration: 3.4)
        }
    }
}

struct MascotMotion {
    let floatOffset: CGFloat
    let tilt: Double
    let scale: CGFloat
    let duration: Double
}

struct OnboardingMascotView: View {
    let scene: OnboardingMascotScene
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        mascotImage
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(reduceMotion ? 0 : (animate ? scene.motion.tilt : -scene.motion.tilt)))
            .scaleEffect(reduceMotion ? 1 : (animate ? scene.motion.scale : 1.0))
            .offset(y: reduceMotion ? 0 : (animate ? -scene.motion.floatOffset : scene.motion.floatOffset))
            .animation(reduceMotion ? nil : .easeInOut(duration: scene.motion.duration).repeatForever(autoreverses: true), value: animate)
            .onAppear {
                animate = true
            }
            .accessibilityHidden(true)
    }

    private var mascotImage: Image {
        if UIImage(named: "onboarding_mascot_base") != nil {
            Image("onboarding_mascot_base")
        } else {
            Image("AppIconInternal")
        }
    }
}
