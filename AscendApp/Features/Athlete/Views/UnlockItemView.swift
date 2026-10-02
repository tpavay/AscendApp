import SwiftUI

/// One item from an event page: the climber's whole athlete wearing it, head to feet, where it
/// really goes - a pumpkin on the shoulder, a giant pressed overhead - with what it takes and, once
/// earned, EQUIP. A locked item is shown on the athlete too, so the climber sees what they are
/// climbing for.
struct UnlockItemView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var unlocks: UnlockStore
    @State private var looks: AthleteLookStore
    @State private var isEquipping = false
    @State private var showingBanner = false
    @State private var equipFailed = false
    @State private var showingAthlete = false

    let item: UnlockItem
    let event: UnlockEvent
    let progress: UnlockEventProgress?
    let onStartClimbing: () -> Void
    private let userId: (() -> String?)?

    init(
        item: UnlockItem,
        event: UnlockEvent,
        progress: UnlockEventProgress?,
        unlocks: UnlockStore = .shared,
        looks: AthleteLookStore = .shared,
        userId: (() -> String?)? = nil,
        onStartClimbing: @escaping () -> Void
    ) {
        self.item = item
        self.event = event
        self.progress = progress
        self.userId = userId
        self.onStartClimbing = onStartClimbing
        _unlocks = State(initialValue: unlocks)
        _looks = State(initialValue: looks)
    }

    private var signedInUser: String? {
        userId?() ?? authVM.user?.uid
    }

    private var isEarned: Bool {
        unlocks.earned.contains(item.shape) || progress?.isEarned(item) == true
    }

    private var isWorn: Bool {
        looks.current.gear.contains(item.shape)
    }

    /// The climber's own athlete with this item on, whatever else they wear.
    private var tryOn: AthleteLook {
        var look = looks.current
        look.equip(item.shape)
        return look
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    stage
                    info
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    if !isEarned {
                        progressCard
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }
                    Button {
                        showingAthlete = true
                    } label: {
                        Text("OPEN YOUR ATHLETE")
                            .font(.montserratBold(size: 12))
                            .tracking(1)
                            .foregroundStyle(Color.accent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            dockButton
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color.black.ignoresSafeArea(edges: .bottom))
        }
        .overlay(alignment: .top) {
            if showingBanner {
                banner
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .trackOnce(screen: .unlockItem)
        .sheet(isPresented: $showingAthlete) {
            AthleteEditorView(store: looks, unlocks: unlocks, userId: userId)
                .appSheetStyle(.large)
        }
        .task(id: signedInUser) {
            guard let userId = signedInUser else { return }
            if isEarned { unlocks.markSeen([item.shape], userId: userId) }
            _ = await looks.load(userId: userId)
        }
    }

    private var navBar: some View {
        ZStack {
            Text(event.title.uppercased())
                .font(.montserratBold(size: 10.5))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.6))
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 4)
    }

    private var stage: some View {
        AthletePreviewView(look: tryOn, turns: false)
            .frame(height: 290)
            .frame(maxWidth: .infinity)
            .brightness(isEarned ? 0 : -0.15)
            .saturation(isEarned ? 1 : 0.7)
            .background(UnlockStyle.stageGlow)
            .overlay(alignment: .topTrailing) {
                if !isEarned {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("LOCKED")
                            .font(.montserratBold(size: 10))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Capsule(style: .continuous).fill(.white.opacity(0.1)))
                    .padding(.top, 10)
                    .padding(.trailing, 20)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your athlete with the \(item.shape.title)")
            .accessibilityValue(isEarned ? "" : "Locked")
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UnlockCopy.slotLine(item.shape))
                .font(.montserratBold(size: 11))
                .tracking(1.6)
                .foregroundStyle(UnlockStyle.pumpkin)
            Text(item.shape.title)
                .font(.montserratBold(size: 30))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text(UnlockCopy.rule(item, in: event))
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .padding(.top, 8)
            if isEarned {
                Text("Earned in \(event.monthName)")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var progressCard: some View {
        if let progress, let counted = UnlockItemProgress(item: item, progress: progress) {
            VStack(spacing: 8) {
                HStack {
                    Text("\(counted.have.formatted()) of \(counted.need.formatted()) \(counted.unit)")
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text("\(counted.remaining.formatted()) to go")
                        .foregroundStyle(Color.accent)
                }
                .font(.montserratBold(size: 12))
                .monospacedDigit()
                UnlockProgressBar(fraction: counted.fraction, height: 8, fill: AnyShapeStyle(Color.accent), minimum: 0.02)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var dockButton: some View {
        if !isEarned {
            UnlockDockButton(title: "START CLIMBING", style: .pumpkin, height: 56, action: onStartClimbing)
        } else if isWorn {
            UnlockDockButton(title: "EQUIPPED", style: .done, height: 56) {}
                .accessibilityAddTraits(.isSelected)
        } else {
            VStack(spacing: 8) {
                if equipFailed {
                    Text("Couldn't equip it. Try again.")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                }
                UnlockDockButton(title: isEquipping ? "EQUIPPING..." : "EQUIP", style: .lime, height: 56, action: equip)
                    .disabled(isEquipping || signedInUser == nil)
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 12) {
            Image(item.shape.thumbnailName)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.shape.title) equipped")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)
                Text("Everyone on the stairs sees it.")
                    .font(.montserratBold(size: 11.5))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 20 / 255, green: 22 / 255, blue: 25 / 255).opacity(0.96))
                .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.accent.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func equip() {
        guard let userId = signedInUser else { return }
        isEquipping = true
        equipFailed = false
        Task {
            defer { isEquipping = false }
            do {
                try await looks.equip(item.shape, userId: userId)
                unlocks.markSeen([item.shape], userId: userId)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showingBanner = true }
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeIn(duration: 0.3)) { showingBanner = false }
            } catch {
                equipFailed = true
                TelemetryManager.shared.recordError(error, context: .firestore, code: "athlete_look_equip_failed")
            }
        }
    }
}
