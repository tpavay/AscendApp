import XCTest

@MainActor
final class ReturningSubscriberJourneyUITests: XCTestCase {
    func testActiveSubscriberSignsOutAndReturnsToTheirDataWithoutPaywall() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestReturningSubscriberJourney",
            "-FIRDebugDisabled"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["tab.Home"].waitForExistence(timeout: 15))

        app.buttons["tab.Profile"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.buttons["accountSignOut"].waitForExistence(timeout: 10))
        app.buttons["accountSignOut"].tap()
        XCTAssertTrue(app.alerts["Sign Out"].waitForExistence(timeout: 5))
        app.alerts["Sign Out"].buttons["Sign Out"].tap()

        XCTAssertTrue(app.buttons["welcomeSignIn"].waitForExistence(timeout: 10))
        app.buttons["welcomeSignIn"].tap()

        let googleSignIn = app.buttons["CONTINUE WITH GOOGLE"]
        XCTAssertTrue(googleSignIn.waitForExistence(timeout: 10))
        googleSignIn.tap()

        XCTAssertTrue(app.buttons["tab.Home"].waitForExistence(timeout: 15))
        XCTAssertFalse(element("appAccessPaywallLoading", in: app).exists)

        let paywallRegistrations = element(
            "returningSubscriberJourney.paywallRegistrations",
            in: app
        )
        XCTAssertTrue(paywallRegistrations.waitForExistence(timeout: 5))
        XCTAssertEqual(paywallRegistrations.value as? String, "0")

        app.buttons["tab.Profile"].tap()
        XCTAssertTrue(app.buttons["Activity"].waitForExistence(timeout: 10))
        app.buttons["Activity"].tap()
        XCTAssertTrue(
            app.staticTexts["Returning Subscriber Workout"].waitForExistence(timeout: 10)
        )
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
