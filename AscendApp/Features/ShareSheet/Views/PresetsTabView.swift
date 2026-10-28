import PhotosUI
import SwiftUI

/// The Presets tab: the swipeable card, the three-way customisation bar with its panel, and the
/// Story, Copy, Save and More actions.
struct PresetsTabView: View {
    let model: PresetsViewModel
    let sheet: ShareSheetViewModel
    let workout: Workout
    let climb: Climb?

    @State private var showsPhotoSheet = false

    private let lime = Color(shareHex: PresetAccent.lime.hex)

    var body: some View {
        VStack(spacing: 0) {
            PresetCardPager(model: model)
                .padding(.top, 20)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(model.layouts) { layout in
                        Capsule()
                            .fill(layout == model.currentLayout ? lime : Color(shareHex: 0x3A3A3A))
                            .frame(width: layout == model.currentLayout ? 18 : 6, height: 6)
                            .onTapGesture { model.select(layout: layout) }
                            .accessibilityLabel("\(layout.title) layout")
                    }
                }
                Text(model.layoutCaption)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color(shareHex: 0x8A8A8A))
            }
            .padding(.top, 14)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if model.panel != nil {
                    PresetPanelView(model: model, onChoosePhoto: { showsPhotoSheet = true })
                        .zIndex(1)
                }
                PresetCustomizationBar(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            PresetActionRow(isBusy: sheet.busyAction != nil) { action in
                Task { await sheet.perform(action, model: model.cardModel, artwork: model.artwork) }
            }
        }
        .sheet(isPresented: $showsPhotoSheet) {
            PresetPhotoSheet(model: model, climbWindow: climbWindow)
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(shareHex: 0x121212))
        }
    }

    /// The climb's own time span, for the photos taken during it.
    private var climbWindow: DateInterval {
        DateInterval(start: workout.date, duration: max(workout.duration, 1))
    }
}
