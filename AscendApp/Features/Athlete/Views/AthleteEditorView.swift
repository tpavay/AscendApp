import SwiftUI

/// Where a climber makes their athlete theirs: everything they have earned to wear, then body,
/// skin, hair and its colour, the colours of the tank, shorts and shoes, size and muscle. The
/// athlete turns above the choices and wears each one the moment it is tapped; nothing is kept
/// until SAVE ATHLETE. It is the one place a climber's gear lives.
///
/// Opened from the onboarding step, the Profile card and the Just Climb setup sheet.
struct AthleteEditorView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var unlocks: UnlockStore
    /// Each opened event's climbs and steps so far, read once the editor opens.
    @State private var eventProgress: [UnlockEventProgress] = []
    @State private var didSave = false

    /// Called once the look is saved, before the editor closes.
    var onSaved: () -> Void = {}

    @State private var model: AthleteEditorModel
    private let store: AthleteLookStore

    private let userId: (() -> String?)?

    init(store: AthleteLookStore = .shared, unlocks: UnlockStore = .shared, userId: (() -> String?)? = nil, onSaved: @escaping () -> Void = {}) {
        self.store = store
        self.userId = userId
        self.onSaved = onSaved
        _unlocks = State(initialValue: unlocks)
        _model = State(initialValue: AthleteEditorModel(look: store.current))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 22)

            AthletePreviewView(look: model.draft)
                .frame(height: 290)
                .frame(maxWidth: .infinity)
                .opacity(model.isEditable ? 1 : 0.35)
                .overlay {
                    if model.savedLookRead == .reading {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .background(stageGlow)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if unlocks.isEnabled, !gearEntries.isEmpty {
                        AthleteGearRows(
                            entries: gearEntries,
                            owned: unlocks.earned.union(store.current.gear),
                            new: unlocks.newItems,
                            wearing: model.draft.gear,
                            onWear: { item in
                                model.wear(item)
                                didSave = false
                                if let userId = signedInUser { unlocks.markSeen([item], userId: userId) }
                            },
                            onTakeOff: { item in
                                model.takeOff(item)
                                didSave = false
                            }
                        )
                        .padding(.bottom, 4)
                    }
                    section("BODY") {
                        AthleteChoiceStrip(
                            options: AthleteLook.Body.allCases,
                            selection: Binding(get: { model.draft.body }, set: { model.choose(body: $0) }),
                            title: \.title,
                            accessibilityPrefix: "Body"
                        )
                    }
                    section("SKIN") {
                        AthleteSwatchRow(
                            options: AthleteLook.SkinTone.allCases,
                            selection: $model.draft.skinTone,
                            color: { $0.color },
                            accessibilityName: { tone in "Skin tone \((AthleteLook.SkinTone.allCases.firstIndex(of: tone) ?? 0) + 1) of \(AthleteLook.SkinTone.allCases.count)" }
                        )
                    }
                    section("HAIR") {
                        VStack(alignment: .leading, spacing: 12) {
                            AthleteChoiceStrip(
                                options: AthleteLook.HairStyle.allCases,
                                selection: $model.draft.hairStyle,
                                title: \.title,
                                accessibilityPrefix: "Hair"
                            )
                            AthleteSwatchRow(
                                options: AthleteLook.HairColor.allCases,
                                selection: $model.draft.hairColor,
                                color: { $0.color },
                                accessibilityName: { "\(AthleteLookDescription.hairColorName($0).capitalized) hair" }
                            )
                        }
                    }
                    section("TANK · SHORTS · SHOES") {
                        VStack(alignment: .leading, spacing: 12) {
                            AthleteChoiceStrip(
                                options: AthleteEditorModel.Garment.allCases,
                                selection: $model.garment,
                                title: \.title,
                                accessibilityPrefix: "Colour for"
                            )
                            AthleteSwatchRow(
                                options: AthleteLook.KitColor.allCases,
                                selection: $model.kitColor,
                                color: { $0.color },
                                accessibilityName: { "\($0.rawValue.capitalized) \(model.garment.rawValue)" }
                            )
                        }
                    }
                    section("SIZE") {
                        AthleteChoiceStrip(
                            options: AthleteLook.Size.allCases,
                            selection: $model.draft.size,
                            title: \.title,
                            accessibilityPrefix: "Size"
                        )
                    }
                    section("MUSCLE") {
                        AthleteChoiceStrip(
                            options: AthleteLook.Muscle.allCases,
                            selection: $model.draft.muscle,
                            title: \.title,
                            accessibilityPrefix: "Muscle"
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .disabled(!model.isEditable)
            .opacity(model.isEditable ? 1 : 0.45)

            saveBar
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .trackOnce(screen: .athleteEditor)
        .task(id: signedInUser) {
            if let userId = signedInUser, unlocks.isEnabled {
                await unlocks.refreshCatalogIfNeeded()
                eventProgress = unlocks.refresh(userId: userId, modelContext: modelContext)
            }
            await loadSavedLook()
        }
    }

    private var signedInUser: String? {
        userId?() ?? authVM.user?.uid
    }

    /// Every item the climber can wear or work toward, from every event that has opened, newest
    /// event first. A retired item stays for whoever owns it, so it can still come off.
    private var gearEntries: [AthleteGearRows.Entry] {
        let owned = unlocks.earned.union(store.current.gear)
        return eventProgress.flatMap { progress in
            unlocks.catalog.gearItems(of: progress.event, owned: owned).map { AthleteGearRows.Entry(item: $0, progress: progress) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("YOUR ATHLETE")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var stageGlow: some View {
        RadialGradient(
            colors: [Color(red: 0.11, green: 0.14, blue: 0.07), .black],
            center: UnitPoint(x: 0.5, y: 0.72),
            startRadius: 0,
            endRadius: 210
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.montserratBold(size: 11))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.48))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var saveBar: some View {
        VStack(spacing: 10) {
            if model.savedLookRead == .failed {
                HStack(spacing: 12) {
                    Text("Couldn't load your athlete.")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("TRY AGAIN") {
                        Task { await loadSavedLook() }
                    }
                    .font(.montserratBold(size: 12))
                    .tracking(1)
                    .foregroundStyle(Color.accent)
                    .buttonStyle(.plain)
                }
            } else if model.saveFailed {
                Text("Couldn't save your athlete. Try again.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                save()
            } label: {
                Text(didSave ? "SAVED" : model.isSaving ? "SAVING..." : "SAVE ATHLETE")
                    .font(.montserratBold(size: 14))
                    .tracking(1.1)
                    .foregroundStyle(didSave ? Color.accent : .black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                        if didSave {
                            shape.fill(Color.accent.opacity(0.16)).overlay(shape.strokeBorder(Color.accent.opacity(0.6), lineWidth: 1.5))
                        } else {
                            shape.fill(Color.accent.opacity(model.canSave ? 1 : 0.6))
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!model.canSave || didSave || signedInUser == nil)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.black)
        .overlay(alignment: .top) {
            // The choices scroll away under the button instead of ending on a hard line.
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .offset(y: -22)
                .allowsHitTesting(false)
        }
    }

    private func loadSavedLook() async {
        guard let userId = signedInUser else { return }
        await model.loadSavedLook(userId: userId, from: store)
    }

    private func save() {
        guard let userId = signedInUser else { return }
        Task {
            if await model.save(userId: userId, to: store) {
                withAnimation(.smooth(duration: 0.18)) { didSave = true }
                onSaved()
                try? await Task.sleep(for: .milliseconds(650))
                dismiss()
            }
        }
    }
}

/// One choice among a few words, the way every picker in Ascend's climb sheets looks: a
/// capsule track with the chosen word on lime.
struct AthleteChoiceStrip<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: KeyPath<Option, String>
    let accessibilityPrefix: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.smooth(duration: 0.18)) {
                        selection = option
                    }
                } label: {
                    Text(option[keyPath: title].uppercased())
                        .font(.montserratBold(size: 11))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous).fill(Color.accent)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accessibilityPrefix) \(option[keyPath: title])")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.white.opacity(0.07), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

/// A row of colour swatches; the chosen one wears a lime ring.
struct AthleteSwatchRow<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let color: (Option) -> MountainColor
    let accessibilityName: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    selection = option
                } label: {
                    Circle()
                        .fill(Color(uiColor: color(option).uiColor))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                        .padding(4)
                        .overlay {
                            if isSelected {
                                Circle().stroke(Color.accent, lineWidth: 2.5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityName(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
