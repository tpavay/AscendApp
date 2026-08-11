import Testing
@testable import AscendApp

/// This suite exists as much for where it compiles as for what it asserts.
/// `AscendWatchShared/` is a synchronized root group listed in both the app
/// target's and the watch target's `fileSystemSynchronizedGroups`, and the app
/// target compiling this file is the iOS half of that proof. The watch half is
/// the watch target's own compile of the same source.
struct AscendWatchSharedTests {
    @Test("The watch bundle identifier is its companion's plus the watchkitapp suffix")
    func watchBundleIdentifierDerivesFromCompanion() {
        #expect(AscendWatchShared.watchAppBundleIdentifierSuffix == ".watchkitapp")
        #expect(
            AscendWatchShared.watchAppBundleIdentifier(companion: "com.TylerPavay.AscendApp")
                == "com.TylerPavay.AscendApp.watchkitapp"
        )
        #expect(
            AscendWatchShared.watchAppBundleIdentifier(companion: "com.TylerPavay.AscendApp.staging")
                == "com.TylerPavay.AscendApp.staging.watchkitapp"
        )
        #expect(
            AscendWatchShared.watchAppBundleIdentifier(companion: "com.TylerPavay.AscendApp.dev")
                == "com.TylerPavay.AscendApp.dev.watchkitapp"
        )
    }
}
