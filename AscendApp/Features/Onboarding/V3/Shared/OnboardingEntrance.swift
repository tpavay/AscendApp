import SwiftUI

extension EnvironmentValues {
    /// Forces Reduce Motion on or off for a rendered test, which cannot set the system's read-only
    /// value. Nil, always in the app, follows the system.
    @Entry var onboardingReduceMotionOverride: Bool?
}

/// Whether the onboarding screens should drop their motion.
@propertyWrapper
struct OnboardingReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.onboardingReduceMotionOverride) private var override

    var wrappedValue: Bool { override ?? system }
}

/// The entrance every v3 element makes: it fades in and rises about 16 pt on the design's curve,
/// staggered by `index`. The pop variant is for badges and chips and overshoots on the way in.
///
/// Reduce Motion keeps the fade and drops everything that moves.
struct OnboardingEntrance: ViewModifier {
    enum Style {
        /// Opacity 0 to 1 and a rise of `rise` points over 0.5 s.
        case rise(CGFloat = 16)
        /// Scale 0.6 to 1.08 to 1 over 0.5 s.
        case pop
    }

    /// The design's `cubic-bezier(.2, .8, .2, 1)`.
    static func curve(duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
    }

    /// The gap between consecutive indexes.
    static let stagger = 0.15

    var index = 0
    var style: Style = .rise()
    /// Added to the stagger, for an element the design starts at an absolute time (0.7 s, 0.95 s).
    var delay: Double = 0
    var duration: Double = 0.5

    @OnboardingReduceMotion private var reduceMotion
    @State private var hasAppeared = false

    private var startDelay: Double { delay + Self.stagger * Double(index) }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(hasAppeared ? 1 : 0)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.3).delay(startDelay)) { hasAppeared = true }
                }
        } else {
            switch style {
            case .rise(let distance):
                content
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : distance)
                    .onAppear {
                        withAnimation(Self.curve(duration: duration).delay(startDelay)) { hasAppeared = true }
                    }
            case .pop:
                content
                    .keyframeAnimator(
                        initialValue: PopFrame.start,
                        trigger: hasAppeared
                    ) { view, frame in
                        view.scaleEffect(frame.scale).opacity(frame.opacity)
                    } keyframes: { _ in
                        Self.popKeyframes(startDelay: startDelay, duration: duration)
                    }
                    .onAppear { hasAppeared = true }
            }
        }
    }

    struct PopFrame {
        static let start = PopFrame(scale: 0.6, opacity: 0)

        var scale: Double
        var opacity: Double
    }

    /// The shortest lead-in hold: a zero-duration keyframe before a cubic one makes the track report
    /// a NaN scale, and the keyframe builder has no `if` to leave the hold out.
    private static let minimumLeadIn = 0.001

    @KeyframesBuilder<PopFrame>
    static func popKeyframes(startDelay: Double, duration: Double) -> some Keyframes<PopFrame> {
        KeyframeTrack(\.opacity) {
            LinearKeyframe(PopFrame.start.opacity, duration: max(startDelay, minimumLeadIn))
            LinearKeyframe(1, duration: duration * 0.4)
        }
        KeyframeTrack(\.scale) {
            LinearKeyframe(PopFrame.start.scale, duration: max(startDelay, minimumLeadIn))
            CubicKeyframe(1.08, duration: duration * 0.6)
            CubicKeyframe(1, duration: duration * 0.4)
        }
    }
}

extension View {
    func onboardingEntrance(
        index: Int = 0,
        style: OnboardingEntrance.Style = .rise(),
        delay: Double = 0,
        duration: Double = 0.5
    ) -> some View {
        modifier(OnboardingEntrance(index: index, style: style, delay: delay, duration: duration))
    }
}
