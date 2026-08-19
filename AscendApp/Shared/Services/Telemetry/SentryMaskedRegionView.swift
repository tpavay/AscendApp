import UIKit

/// An invisible view whose frame Sentry paints over in every crash screenshot.
///
/// Sentry redacts by view class, and its text and image classes miss anything an
/// app draws itself. Ascend's heart-rate and trend charts are exactly that: Swift
/// Charts renders its marks and its axis labels through drawing layers the SDK
/// does not recognise, so a masked screenshot of Workout Detail still showed the
/// climber's whole heart-rate trace with real BPM values on the axis. Registering
/// this class in `maskedViewClasses` and overlaying it (`View.sentryMasked()`)
/// puts the region back under the SDK's control without the app having to know
/// what SwiftUI called its layers this release.
///
/// UIKit is deliberate here - the SDK's redaction walks a `UIView` tree, so a
/// pure-SwiftUI marker would be invisible to it.
///
/// The view is transparent but not zero-opacity: the redaction walk skips any
/// layer whose `opacity` is 0, so an `alpha` of 0 would silently un-mask the very
/// surface this exists to cover.
final class SentryMaskedRegionView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
