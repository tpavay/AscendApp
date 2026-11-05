import SwiftUI

/// 11: this month's event, read from the hosted unlock catalogue. The event that is on, an event
/// that starts within a week, or the neutral version with no gear and nothing dated - never an
/// event that has ended. Every word of an event comes from the catalogue, so next month's screen
/// needs no app update.
struct OnboardingThisMonthEventScreen: View {
    let coordinator: OnboardingV3Coordinator

    private let model: OnboardingMonthlyEventModel
    private let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoomed = false

    init(
        coordinator: OnboardingV3Coordinator,
        model: OnboardingMonthlyEventModel = .shared,
        now: Date = .now
    ) {
        self.coordinator = coordinator
        self.model = model
        self.now = now
    }

    private var presentation: OnboardingMonthlyEvent {
        model.presentation(now: now)
    }

    var body: some View {
        let content = ThisMonthEventContent(
            presentation: presentation,
            landmarkCount: model.availableLandmarkCount,
            usualClimbSteps: coordinator.answers.usualClimbSteps,
            usualClimbMinutes: coordinator.answers.usualClimbMinutes,
            weeklyTarget: coordinator.answers.weeklyTargetDays.flatMap(WeeklyTarget.init(days:))
        )

        GeometryReader { proxy in
            ZStack(alignment: .top) {
                art(height: proxy.size.height * 0.66)

                VStack(spacing: 0) {
                    OnboardingProgressHeader(step: .thisMonthEvent)
                        .padding(.top, 9)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Color.clear.frame(height: proxy.size.height < 720 ? 4 : max(proxy.size.height * 0.2, 40))

                            copyColumn(content)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    Button("Let's climb") { coordinator.advance() }
                        .buttonStyle(.onboardingPrimary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
        }
        .task {
            model.prefetch()
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 4)) { zoomed = true }
        }
        .trackOnce(screen: .onboardingThisMonthEvent)
    }

    // MARK: - Art

    /// The event's themed art when it has one, else a landmark photograph. It zooms from 1.15 to 1
    /// over four seconds and fades into black behind the copy.
    private func art(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [OnboardingV3Palette.accent.opacity(0.28), Color(hex: "0A0A0A")],
                startPoint: .top,
                endPoint: .bottom
            )

            if isHaunted {
                Color.clear.overlay {
                    Image("Seasonal/HauntedStairwell")
                        .resizable()
                        .scaledToFill()
                }
            } else if let landmark = model.heroLandmark {
                ClimbArtworkView(climb: landmark, variant: .hero)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        // The zoom is clipped back to the frame before the fade is laid over it, so the art can
        // never draw past the gradient that darkens it.
        .scaleEffect(reduceMotion || zoomed ? 1 : 1.15)
        .clipped()
        .overlay(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.7), location: 0.72),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }

    private var isHaunted: Bool {
        guard case .running(let running) = presentation else { return false }
        return running.event.theme?.style == .haunted
    }

    // MARK: - Copy

    @ViewBuilder
    private func copyColumn(_ content: ThisMonthEventContent) -> some View {
        Text(content.kicker)
            .onboardingKicker()
            .onboardingEntrance(index: 0)

        OnboardingHeadline(content.headlineLines, accentLines: [])
            .onboardingEntrance(index: 1)

        Text(content.subline)
            .onboardingBody()
            .onboardingEntrance(index: 2)

        if !content.pieces.isEmpty {
            pieceRow(content.pieces)
                .padding(.top, 4)
        }

        if !content.tiles.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(content.tiles.enumerated()), id: \.offset) { index, tile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.value)
                            .font(.custom("Montserrat-Black", size: 24))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(tile.label)
                            .font(.custom("Montserrat-ExtraBold", size: 10))
                            .tracking(1.6)
                            .foregroundStyle(OnboardingV3Palette.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .onboardingCard(cornerRadius: 16)
                    .accessibilityElement(children: .combine)
                    .onboardingEntrance(index: index + 4, duration: 0.45)
                }
            }
        }

        if let fineLine = content.fineLine {
            Text(fineLine)
                .onboardingSecondary()
        }
    }

    private func pieceRow(_ pieces: [OnboardingMonthlyEvent.Piece]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                VStack(spacing: 6) {
                    Image(piece.gear.thumbnailName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 64)
                        .modifier(PieceBob(isActive: !reduceMotion, phase: Double(index) * 0.5))

                    Text(piece.label)
                        .font(.custom("Montserrat-ExtraBold", size: 10))
                        .tracking(1.2)
                        .foregroundStyle(piece.label == "YOURS TODAY" ? OnboardingV3Palette.accent : OnboardingV3Palette.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(piece.name), \(piece.label.capitalized)")
                .onboardingEntrance(index: 0, style: .pop, delay: 0.5 + Double(index) * 0.1, duration: 0.5)
                .task {
                    // A light tap as each piece lands, 0.1 s apart.
                    try? await Task.sleep(for: .milliseconds(Int(500 + Double(index) * 100)))
                    HapticsManager.shared.trigger(.lightImpact)
                }
            }
        }
    }
}

/// A gentle bob on a 3.6 second loop, each piece a half beat from the one before it.
private struct PieceBob: ViewModifier {
    let isActive: Bool
    let phase: Double
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -4 : 3)
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(phase)) {
                    up = true
                }
            }
    }
}

#Preview("11 this month's event") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-event") ?? .standard),
        startingAt: .thisMonthEvent
    ))
}
