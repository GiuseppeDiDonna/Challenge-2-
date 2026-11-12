import XCTest

final class FocusCheckInUITests: XCTestCase {
    @MainActor
    func testPredictionUpdatesAndDurationBoundaries() {
        let app = isolatedApp()
        app.launch()

        let duration = app.textFields["plannedMinutes"]
        XCTAssertEqual(duration.value as? String, "45")
        XCTAssertTrue(app.staticTexts["Seleziona l’energia per vedere le stime."].exists)

        selectEnergy("Media", in: app)
        // Reference percentages from the bundled synthetic-v1 model on macOS.
        assertVisible(["35 min", "45 min · Durata scelta", "55 min", "70.7%", "68.5%", "66.2%"], in: app)

        selectEnergy("Alta", in: app)
        assertVisible(["82.2%", "80.7%", "79.0%"], in: app)
        XCTAssertFalse(app.staticTexts["68.5%"].exists)

        replaceDuration(with: "5", in: app)
        assertVisible(["5 min · Durata scelta", "15 min"], in: app)
        XCTAssertFalse(app.staticTexts["-5 min"].exists)
        XCTAssertFalse(app.staticTexts["25 min"].exists)

        replaceDuration(with: "180", in: app)
        assertVisible(["170 min", "180 min · Durata scelta"], in: app)
        XCTAssertFalse(app.staticTexts["190 min"].exists)

        replaceDuration(with: "181", in: app)
        assertVisible(["Inserisci una durata tra 5 e 180 minuti."], in: app)
        XCTAssertFalse(app.staticTexts["180 min · Durata scelta"].exists)
    }

    @MainActor
    func testEarlyStopAndFeedbackSurviveRelaunchWithoutSleep() {
        let app = isolatedApp()
        app.launch()
        selectEnergy("Alta", in: app)
        app.buttons["Inizia sessione"].tap()

        app.terminate()
        app.launch()
        let stop = app.buttons["Termina prima"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.buttons["Per stanchezza"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.buttons["Per stanchezza"].tap()
        XCTAssertTrue(app.textFields["plannedMinutes"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        let pilot = app.buttons["Verifica del pilot"]
        XCTAssertTrue(pilot.waitForExistence(timeout: 5))
        pilot.tap()
        let count = app.descendants(matching: .any)["pilotSessionCount"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.value as? String, "1")
    }

    @MainActor
    func testTimerOpensCompletionFeedbackAtDeadline() {
        let app = isolatedApp()
        app.launchArguments += ["-focusTestNearDeadline", "YES"]
        app.launch()

        let finished = app.buttons["Durata giusta"]
        XCTAssertTrue(finished.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Avrei continuato"].exists)
        XCTAssertFalse(app.buttons["Per stanchezza"].exists)
        finished.tap()
        XCTAssertTrue(app.textFields["plannedMinutes"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func isolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-focusTestHistory", UUID().uuidString, "-readsSleepFromHealth", "NO"]
        return app
    }

    @MainActor
    private func selectEnergy(_ label: String, in app: XCUIApplication) {
        app.descendants(matching: .any).matching(identifier: "initialEnergy").firstMatch.tap()
        app.buttons[label].tap()
    }

    @MainActor
    private func replaceDuration(with value: String, in app: XCUIApplication) {
        let field = app.textFields["plannedMinutes"]
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
        app.buttons["Fine"].tap()
    }

    @MainActor
    private func assertVisible(_ labels: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for label in labels {
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 2), label, file: file, line: line)
        }
    }
}
