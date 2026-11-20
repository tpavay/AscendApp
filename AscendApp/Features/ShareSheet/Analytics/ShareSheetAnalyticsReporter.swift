import Foundation

/// The one place the share sheet's events are built and handed to telemetry, so a view model
/// states what happened and never assembles a payload.
///
/// One reporter belongs to one sheet session and is shared by its view models: it carries the
/// source and the climb every event in that session shares, and the running tally of edits that
/// rides on every share.
@MainActor
final class ShareSheetAnalyticsReporter {
    let context: ShareSheetAnalyticsContext
    private let telemetry: TelemetryManager
    private(set) var edits = ShareEditSummary()

    init(context: ShareSheetAnalyticsContext, telemetry: TelemetryManager = .shared) {
        self.context = context
        self.telemetry = telemetry
    }

    func cardSelected(_ layout: PresetLayout) {
        telemetry.track(ShareSheetAnalyticsEvent.cardSelected(context: context, layout: layout))
    }

    /// `value` is a member of a bounded set (a font, an accent, a background kind), never anything
    /// the climber typed or chose from their own library.
    func edited(_ kind: ShareEditKind, value: String) {
        edits.record(kind)
        telemetry.track(ShareSheetAnalyticsEvent.cardEdited(context: context, kind: kind, value: value))
    }

    func actionTapped(_ action: ShareAction, content: ShareContent) {
        telemetry.track(
            ShareSheetAnalyticsEvent.actionTapped(context: context, action: action, content: content, edits: edits)
        )
    }

    /// `destination` defaults to where the action was aiming, which is right for every outcome
    /// except the system sheet, whose handler reports the real one.
    func activityFinished(
        _ action: ShareAction,
        content: ShareContent,
        outcome: ShareOutcome,
        destination: ShareDestination? = nil
    ) {
        telemetry.track(
            ShareSheetAnalyticsEvent.activityCompleted(
                context: context,
                action: action,
                content: content,
                edits: edits,
                destination: destination ?? action.intendedDestination,
                outcome: outcome
            )
        )
    }
}
