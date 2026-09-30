import SwiftUI

/// Who races the climber on the Mountain, changed mid-climb with the hands still on the rails:
/// every row is one tap, and a change reaches the stairs at once. Everyone narrows to chosen
/// climbers through Filter, which opens `filterScreen`.
struct AscendMountainRaceSheet<FilterScreen: View>: View {
    @Bindable var race: AscendMountainRace
    /// Nobody else has finished this board, so there is nobody for Everyone to show.
    let isAloneOnBoard: Bool
    @ViewBuilder let filterScreen: () -> FilterScreen

    @State private var showingFilter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO YOU RACE")
                .font(.montserratBold(size: 12))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.56))
                .padding(.bottom, 2)

            row(
                title: "Everyone",
                subtitle: everyoneSubtitle,
                dot: .accent,
                isOn: race.selection.everyone,
                isEnabled: !race.selection.justYou
            ) {
                race.selection.everyone.toggle()
            } accessory: {
                if !isAloneOnBoard {
                    filterLink
                }
            }

            row(
                title: "Your best",
                subtitle: yourBestSubtitle,
                dot: .ascendMedalGold,
                isOn: race.selection.yourBest && race.hasYourBest,
                isEnabled: !race.selection.justYou && race.hasYourBest
            ) {
                race.selection.yourBest.toggle()
            }

            row(
                title: "Pacer",
                subtitle: "Holds \(race.selection.pacerStepsPerMinute) SPM the whole climb",
                dot: Self.pacerBlue,
                isOn: race.selection.pacer,
                isEnabled: !race.selection.justYou
            ) {
                race.selection.pacer.toggle()
            } accessory: {
                if race.selection.pacer && !race.selection.justYou {
                    pacerStepper
                }
            }

            row(
                title: "Just you",
                subtitle: race.selection.justYou ? "Tap again to bring them back" : "Hides everyone",
                dot: .white.opacity(0.35),
                isOn: race.selection.justYou,
                isEnabled: true
            ) {
                race.selection.justYou.toggle()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.18), value: race.selection)
        .sheet(isPresented: $showingFilter) {
            filterScreen()
        }
        .trackOnce(screen: .mountainRace)
    }

    private var everyoneSubtitle: String {
        if isAloneOnBoard { return "Nobody else has finished yet" }
        let chosen = race.selection.chosen.count
        guard chosen > 0 else { return "Every climber's best climb" }
        return chosen == 1 ? "1 climber chosen" : "\(chosen) climbers chosen"
    }

    private var filterLink: some View {
        Button {
            showingFilter = true
        } label: {
            HStack(spacing: 4) {
                Text("Filter")
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .font(.montserratBold(size: 13))
            .foregroundStyle(Color.accent)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.leading, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(race.selection.justYou)
        .accessibilityLabel("Filter climbers")
    }

    /// The pacer's own ice blue, the colour it wears on the stairs.
    private static var pacerBlue: Color { Color(red: 0.75, green: 0.9, blue: 1) }

    private var yourBestSubtitle: String {
        guard let best = race.field.yourBest else { return "No best on this board yet" }
        let steps = "\(Int(best.finalSteps.rounded()).formatted()) steps"
        guard let seconds = best.finishSeconds else { return steps }
        return "\(steps) · \(Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond)))"
    }

    private var pacerStepper: some View {
        HStack(spacing: 0) {
            stepperButton(systemName: "minus", label: "Slower pacer") { race.selection.stepPacer(by: -1) }

            Text("\(race.selection.pacerStepsPerMinute) SPM")
                .font(.montserratBold(size: 15))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            stepperButton(systemName: "plus", label: "Faster pacer") { race.selection.stepPacer(by: 1) }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
    }

    private func stepperButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accent)
                .frame(width: 52, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue("\(race.selection.pacerStepsPerMinute) steps per minute")
    }

    private func row(
        title: String,
        subtitle: String,
        dot: Color,
        isOn: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(dot)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.montserratBold(size: 15))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(.white.opacity(0.56))
                            .contentTransition(.numericText())
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isOn ? Color.accent : .white.opacity(0.3))
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isOn ? .isSelected : [])

            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isOn ? Color.accent : .clear, lineWidth: 1.5)
        )
        .opacity(isEnabled ? 1 : 0.4)
    }
}
