import SwiftUI

/// The weight sheet: a horizontal scale and a unit toggle. It holds its own working value and hands a
/// weight back only when Done is tapped, so opening it on a typical value never saves one.
struct ProfileWeightSheet: View {
    @State private var system: MeasurementSystem
    @State private var step: Int
    private let onUnitChange: (MeasurementSystem) -> Void
    private let onDone: (Double) -> Void

    /// - Parameters:
    ///   - initialKilograms: the stored weight, or `nil` to open at a typical one.
    ///   - onDone: the chosen weight in kilograms.
    init(
        initialKilograms: Double?,
        system: MeasurementSystem,
        onUnitChange: @escaping (MeasurementSystem) -> Void,
        onDone: @escaping (Double) -> Void
    ) {
        _system = State(initialValue: system)
        _step = State(initialValue: Self.step(forKilograms: initialKilograms, system: system))
        self.onUnitChange = onUnitChange
        self.onDone = onDone
    }

    static func step(forKilograms kilograms: Double?, system: MeasurementSystem) -> Int {
        switch system {
        case .imperial: ProfileMeasures.scalePounds(forKilograms: kilograms)
        case .metric: ProfileMeasures.scaleHalfKilograms(forKilograms: kilograms)
        }
    }

    /// What Done stores: the half kilogram exactly, or the pound count converted.
    static func kilograms(forStep step: Int, system: MeasurementSystem) -> Double {
        switch system {
        case .imperial: ProfileMeasures.kilograms(pounds: step)
        case .metric: ProfileMeasures.kilograms(halfKilograms: step)
        }
    }

    var body: some View {
        ProfileSheetFrame(
            title: "Weight",
            units: ProfileSheetUnits(
                options: ["lb", "kg"],
                selected: system == .imperial ? 0 : 1,
                onSelect: switchUnit
            ),
            note: "Profile only, for comparing. Not on leaderboards.",
            onDone: { onDone(Self.kilograms(forStep: step, system: system)) }
        ) {
            VStack(spacing: 18) {
                readout

                ZStack(alignment: .top) {
                    WeightScaleView(system: system, value: $step)
                        .id(system)

                    WeightScaleNeedle()
                        .offset(y: -4)
                }
            }
        }
        .appSheetStyle(.height(ProfileSheetHeight.weight))
    }

    private var readout: some View {
        let kilograms = Self.kilograms(forStep: step, system: system)

        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(system == .imperial ? "\(step)" : ProfileMeasures.kilogramText(kilograms))
                    .font(.custom("Montserrat-Black", fixedSize: 58))
                    .tracking(-58 * 0.03)
                    .foregroundStyle(.white)

                Text(system == .imperial ? "lb" : "kg")
                    .font(.custom("Montserrat-ExtraBold", fixedSize: 20))
                    .foregroundStyle(Color(hex: "8E8E8E"))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Text(alternateText(kilograms: kilograms))
                .font(.custom("Montserrat-Bold", fixedSize: 14))
                .foregroundStyle(Color(hex: "8E8E8E"))
        }
        .accessibilityHidden(true)
    }

    private func alternateText(kilograms: Double) -> String {
        switch system {
        case .imperial: "\(ProfileMeasures.kilogramText(kilograms)) kg"
        case .metric: "\(ProfileMeasures.pounds(kilograms: kilograms)) lb"
        }
    }

    private func switchUnit(to index: Int) {
        let next: MeasurementSystem = index == 0 ? .imperial : .metric
        guard next != system else { return }

        step = next == .imperial
            ? ProfileMeasures.switchWeight(halfKilograms: step)
            : ProfileMeasures.switchWeight(pounds: step)
        system = next
        onUnitChange(next)
    }
}
