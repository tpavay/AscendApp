import SwiftUI

/// The height sheet: a vertical ruler and a unit toggle. It holds its own working value and hands a
/// height back only when Done is tapped, so opening it on a typical value never saves one.
struct ProfileHeightSheet: View {
    @State private var system: MeasurementSystem
    @State private var mark: Int
    private let onUnitChange: (MeasurementSystem) -> Void
    private let onDone: (Double) -> Void

    /// - Parameters:
    ///   - initialCentimeters: the stored height, or `nil` to open at a typical one.
    ///   - onUnitChange: called the moment the climber switches unit, so it is remembered.
    ///   - onDone: the chosen height in centimetres.
    init(
        initialCentimeters: Double?,
        system: MeasurementSystem,
        onUnitChange: @escaping (MeasurementSystem) -> Void,
        onDone: @escaping (Double) -> Void
    ) {
        _system = State(initialValue: system)
        _mark = State(initialValue: Self.mark(forCentimeters: initialCentimeters, system: system))
        self.onUnitChange = onUnitChange
        self.onDone = onDone
    }

    static func mark(forCentimeters centimeters: Double?, system: MeasurementSystem) -> Int {
        switch system {
        case .imperial: ProfileMeasures.rulerInches(forCentimeters: centimeters)
        case .metric: ProfileMeasures.rulerCentimeters(forCentimeters: centimeters)
        }
    }

    /// What Done stores: exact for centimetres, the inch count's centimetres for imperial.
    static func centimeters(forMark mark: Int, system: MeasurementSystem) -> Double {
        switch system {
        case .imperial: ProfileMeasures.centimeters(inches: mark)
        case .metric: Double(mark)
        }
    }

    var body: some View {
        ProfileSheetFrame(
            title: "Height",
            units: ProfileSheetUnits(
                options: ["ft \u{00B7} in", "cm"],
                selected: system == .imperial ? 0 : 1,
                onSelect: switchUnit
            ),
            note: "Profile only, for comparing. Not on leaderboards.",
            onDone: { onDone(Self.centimeters(forMark: mark, system: system)) }
        ) {
            ZStack(alignment: .topLeading) {
                readout
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 4)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HeightRulerView(system: system, value: $mark)
                        .id(system)
                }

                HeightRulerPointer()
                    .padding(.leading, 186)
                    .frame(height: 14)
                    .offset(y: (HeightRulerView.viewHeight - 14) / 2)
            }
            .frame(height: HeightRulerView.viewHeight)
        }
        .appSheetStyle(.height(ProfileSheetHeight.height))
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch system {
            case .imperial:
                Text(ProfileMeasures.rulerReadout(inches: mark))
                    .font(.custom("Montserrat-Black", fixedSize: 58))
                    .tracking(-58 * 0.03)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("\(Int(ProfileMeasures.centimeters(inches: mark).rounded())) cm")
                    .font(.custom("Montserrat-Bold", fixedSize: 14))
                    .foregroundStyle(Color(hex: "8E8E8E"))
            case .metric:
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(mark)")
                        .font(.custom("Montserrat-Black", fixedSize: 58))
                        .tracking(-58 * 0.03)
                        .foregroundStyle(.white)
                    Text("cm")
                        .font(.custom("Montserrat-ExtraBold", fixedSize: 20))
                        .foregroundStyle(Color(hex: "8E8E8E"))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)

                Text(ProfileMeasures.rulerReadout(inches: ProfileMeasures.switchHeight(centimeters: mark)))
                    .font(.custom("Montserrat-Bold", fixedSize: 14))
                    .foregroundStyle(Color(hex: "8E8E8E"))
            }
        }
        .frame(width: 180, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func switchUnit(to index: Int) {
        let next: MeasurementSystem = index == 0 ? .imperial : .metric
        guard next != system else { return }

        mark = next == .imperial
            ? ProfileMeasures.switchHeight(centimeters: mark)
            : ProfileMeasures.switchHeight(inches: mark)
        system = next
        onUnitChange(next)
    }
}
