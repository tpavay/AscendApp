import SwiftUI

/// The one thing Ascend draws while access is being worked out: the system spinner, centred on the
/// app's background, with no words.
///
/// It is the whole app-access gate, behind and between the hosted screens, and the wait before the
/// gate while entitlement is still unknown, so a climber moving between them sees one unbroken
/// screen. Everything a climber reads or taps at the gate is a hosted Superwall screen
/// (`docs/superwall-paywall-setup.md`); nothing here may grow copy or a control.
struct AppAccessSpinnerView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The middle of the screen, not of the safe area: under a Dynamic Island the two are
            // fourteen points apart, and a spinner that sits low reads as misplaced.
            .ignoresSafeArea()
            .themedBackground()
    }
}

#Preview {
    AppAccessSpinnerView()
}
