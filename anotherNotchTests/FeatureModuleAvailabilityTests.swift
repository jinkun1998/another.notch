import XCTest

final class FeatureModuleAvailabilityTests: XCTestCase {
    func testPolishedNotchMotionTiming() {
        let policy = NotchMotionPolicy(reduceMotion: false, style: .polished)

        XCTAssertEqual(policy.openResponse, 0.42, accuracy: 0.001)
        XCTAssertEqual(policy.openDampingFraction, 0.80, accuracy: 0.001)
        XCTAssertEqual(policy.closeDuration, 0.30, accuracy: 0.001)
        XCTAssertEqual(policy.openShell, .spring(response: 0.42, dampingFraction: 0.80))
        XCTAssertEqual(policy.closeShell, .smooth(duration: 0.30))
        XCTAssertEqual(policy.expandedContentRevealDelay, 0.08, accuracy: 0.001)
        XCTAssertEqual(policy.expandedContentRevealDuration, 0.22, accuracy: 0.001)
        XCTAssertEqual(policy.expandedContentHideDuration, 0.12, accuracy: 0.001)
    }

    func testSpringNotchMotionTiming() {
        let policy = NotchMotionPolicy(reduceMotion: false, style: .spring)

        XCTAssertEqual(policy.openResponse, 0.42, accuracy: 0.001)
        XCTAssertEqual(policy.openDampingFraction, 1, accuracy: 0.001)
        XCTAssertEqual(policy.closeDuration, 0.45, accuracy: 0.001)
        XCTAssertEqual(policy.openShell, .spring(response: 0.42, dampingFraction: 1))
        XCTAssertEqual(policy.closeShell, .spring(response: 0.45, dampingFraction: 1))
    }

    func testMinimalNotchMotionTiming() {
        let policy = NotchMotionPolicy(reduceMotion: false, style: .minimal)

        XCTAssertEqual(policy.openResponse, 0.18, accuracy: 0.001)
        XCTAssertEqual(policy.closeDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(policy.openShell, .easeOut(duration: 0.18))
        XCTAssertEqual(policy.closeShell, .easeOut(duration: 0.18))
    }

    func testReduceMotionOverridesEveryNotchMotionStyle() {
        for style in NotchMotionStyle.allCases {
            let policy = NotchMotionPolicy(reduceMotion: true, style: style)

            XCTAssertEqual(policy.openResponse, 0.18, accuracy: 0.001)
            XCTAssertEqual(policy.closeDuration, 0.18, accuracy: 0.001)
            XCTAssertEqual(policy.openShell, .easeOut(duration: 0.18))
            XCTAssertEqual(policy.closeShell, .easeOut(duration: 0.18))
            XCTAssertEqual(policy.expandedContentRevealDelay, 0)
            XCTAssertEqual(policy.expandedContentRevealDuration, 0.14, accuracy: 0.001)
            XCTAssertEqual(policy.expandedContentHideDuration, 0.10, accuracy: 0.001)
        }
    }

    func testScreenBrightnessDisplaySelectionPrefersBuiltInDisplay() {
        let selected = ScreenBrightnessDisplaySelector.select(
            from: [10, 20, 30],
            mainDisplayID: 10,
            isBuiltIn: { $0 == 20 }
        )

        XCTAssertEqual(selected, 20)
    }

    func testScreenBrightnessDisplaySelectionFallsBackToMainDisplay() {
        let selected = ScreenBrightnessDisplaySelector.select(
            from: [20, 30],
            mainDisplayID: 10,
            isBuiltIn: { _ in false }
        )

        XCTAssertEqual(selected, 10)
    }

    func testHomeRemainsEnabledWithoutOptionalFeatureToggles() {
        XCTAssertTrue(
            FeatureModuleAvailability.isMainFeatureEnabled(
                for: .home,
                clipboardHistoryEnabled: false,
                shelfEnabled: false,
                calendarEnabled: false,
                cameraEnabled: false
            )
        )
    }

    func testEachModuleUsesItsOwnMainFeatureToggle() {
        XCTAssertTrue(mainFeatureEnabled(.clipboard, enabledModule: .clipboard))
        XCTAssertTrue(mainFeatureEnabled(.shelf, enabledModule: .shelf))
        XCTAssertTrue(mainFeatureEnabled(.calendar, enabledModule: .calendar))
        XCTAssertTrue(mainFeatureEnabled(.camera, enabledModule: .camera))

        XCTAssertFalse(mainFeatureEnabled(.clipboard, enabledModule: .shelf))
        XCTAssertFalse(mainFeatureEnabled(.shelf, enabledModule: .calendar))
        XCTAssertFalse(mainFeatureEnabled(.calendar, enabledModule: .camera))
        XCTAssertFalse(mainFeatureEnabled(.camera, enabledModule: .clipboard))
    }

    func testModuleAvailabilityRequiresInstallAndEnabledToggle() {
        XCTAssertTrue(
            FeatureModuleAvailability.isAvailable(
                moduleIsAvailable: true,
                isInstalled: true,
                isMainFeatureEnabled: true
            )
        )
        XCTAssertFalse(
            FeatureModuleAvailability.isAvailable(
                moduleIsAvailable: false,
                isInstalled: true,
                isMainFeatureEnabled: true
            )
        )
        XCTAssertFalse(
            FeatureModuleAvailability.isAvailable(
                moduleIsAvailable: true,
                isInstalled: false,
                isMainFeatureEnabled: true
            )
        )
        XCTAssertFalse(
            FeatureModuleAvailability.isAvailable(
                moduleIsAvailable: true,
                isInstalled: true,
                isMainFeatureEnabled: false
            )
        )
    }

    private func mainFeatureEnabled(
        _ module: FeatureModuleID,
        enabledModule: FeatureModuleID
    ) -> Bool {
        FeatureModuleAvailability.isMainFeatureEnabled(
            for: module,
            clipboardHistoryEnabled: enabledModule == .clipboard,
            shelfEnabled: enabledModule == .shelf,
            calendarEnabled: enabledModule == .calendar,
            cameraEnabled: enabledModule == .camera
        )
    }
}
