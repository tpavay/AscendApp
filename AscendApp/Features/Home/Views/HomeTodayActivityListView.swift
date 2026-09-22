import SwiftUI

/// SEE ALL: every row the server holds in the today feed, newest first.
///
/// A Live Climb row pushes Climb Detail from here, so the list stays on the stack and
/// Back returns to it. A Just Climb or routine row leaves the stack for a sheet or
/// another tab, which Home presents, so those are handed back through `onOpen`.
struct HomeTodayActivityListView: View {
    let rows: [ModeratedHomeTodayActivityRow]
    let presentations: [String: HomeTodayActivityRowPresentation]
    let onOpen: (ModeratedHomeTodayActivityRow, HomeTodayActivityRowPresentation) -> Void

    @State private var selectedDetailClimb: Climb?
    private let titleResolver = HomeTodayActivityTitleResolver()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    if let presentation = presentations[row.id] {
                        HomeTodayActivityRowView(row: row, presentation: presentation) {
                            open(row, presentation: presentation)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("On the Globe Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .preferredColorScheme(.dark)
        .navigationDestination(item: $selectedDetailClimb) { climb in
            ClimbDetailView(climb: climb, analyticsEntryPoint: .homeTodayRow)
        }
        .trackOnce(screen: .homeTodayActivityList)
    }

    private func open(
        _ row: ModeratedHomeTodayActivityRow,
        presentation: HomeTodayActivityRowPresentation
    ) {
        if case .climbDetail(let climbId) = presentation.destination {
            guard let climb = titleResolver.openableClimb(for: climbId) else { return }
            selectedDetailClimb = climb
            return
        }
        onOpen(row, presentation)
    }
}
