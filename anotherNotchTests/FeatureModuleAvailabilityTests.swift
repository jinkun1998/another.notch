import AppKit
import Foundation
import XCTest

final class FeatureModuleAvailabilityTests: XCTestCase {
    func testTwoSidedTabsPreserveOrderAndKeepHomeOnTheLeft() {
        let tabOrder: [FeatureModuleID] = [.home, .clipboard, .quickNotes, .shelf]
        let installedIDs: Set<FeatureModuleID> = [.clipboard, .quickNotes, .shelf]
        let rightSideIDs: Set<FeatureModuleID> = [.home, .quickNotes, .shelf]

        XCTAssertEqual(
            FeatureModuleID.tabs(
                in: tabOrder,
                installedIDs: installedIDs,
                rightSideIDs: rightSideIDs,
                twoSidedLayoutEnabled: true,
                side: .left
            ),
            [.home, .clipboard]
        )
        XCTAssertEqual(
            FeatureModuleID.tabs(
                in: tabOrder,
                installedIDs: installedIDs,
                rightSideIDs: rightSideIDs,
                twoSidedLayoutEnabled: true,
                side: .right
            ),
            [.quickNotes, .shelf]
        )
    }

    func testDisabledTwoSidedLayoutKeepsEveryTabOnTheLeft() {
        let tabOrder: [FeatureModuleID] = [.home, .clipboard, .quickNotes]
        let installedIDs: Set<FeatureModuleID> = [.clipboard, .quickNotes]

        XCTAssertEqual(
            FeatureModuleID.tabs(
                in: tabOrder,
                installedIDs: installedIDs,
                rightSideIDs: [.quickNotes],
                twoSidedLayoutEnabled: false,
                side: .left
            ),
            tabOrder
        )
        XCTAssertEqual(
            FeatureModuleID.tabs(
                in: tabOrder,
                installedIDs: installedIDs,
                rightSideIDs: [.quickNotes],
                twoSidedLayoutEnabled: false,
                side: .right
            ),
            []
        )
    }

    func testQuickNotesPersistCreateEditAndDelete() throws {
        let suiteName = "anotherNotchTests.quickNotes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = QuickNoteStore(defaults: defaults, storageKey: "notes")
        let note = store.create()
        store.update(note.id, text: "Buy milk")

        let reloadedStore = QuickNoteStore(defaults: defaults, storageKey: "notes")
        XCTAssertEqual(reloadedStore.notes.map(\.text), ["Buy milk"])

        reloadedStore.delete(note.id)
        XCTAssertTrue(reloadedStore.notes.isEmpty)
    }

    func testVietnameseLunarCalendarConvertsTetAndMidAutumnFestival() {
        XCTAssertEqual(
            VietnameseLunarCalendar.date(day: 10, month: 2, year: 2024),
            VietnameseLunarDate(day: 1, month: 1, year: 2024, isLeapMonth: false)
        )
        XCTAssertEqual(
            VietnameseLunarCalendar.date(day: 17, month: 9, year: 2024),
            VietnameseLunarDate(day: 15, month: 8, year: 2024, isLeapMonth: false)
        )
        XCTAssertEqual(
            VietnameseLunarCalendar.date(day: 17, month: 2, year: 2026),
            VietnameseLunarDate(day: 1, month: 1, year: 2026, isLeapMonth: false)
        )
    }

    func testClosedNotchCPUStaysBelowTenPercent() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_CLOSED_NOTCH_CPU_TEST"] == "1",
            "Set RUN_CLOSED_NOTCH_CPU_TEST=1 to run the machine-dependent CPU check."
        )

        let appURL = Bundle(for: Self.self)
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("anotherNotch (Debug).app")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: appURL.path),
            "Debug app bundle is unavailable."
        )

        let app = try launchApplication(at: appURL)
        defer {
            app.terminate()
        }

        Thread.sleep(forTimeInterval: 5)
        let peakCPUPercent = try XCTUnwrap(cpuSamples(for: app.processIdentifier).max())

        XCTAssertLessThanOrEqual(peakCPUPercent, 10, "Closed notch used \(peakCPUPercent)% CPU.")
    }

    func testIdleSpectrumStopsCPUTimelineUpdates() throws {
        XCTAssertNil(
            ContinuousAnimationPolicy.updateInterval(
                isActive: false,
                reducesMotion: false,
                activeInterval: 1.0 / 45.0
            )
        )
        XCTAssertNil(
            ContinuousAnimationPolicy.updateInterval(
                isActive: true,
                reducesMotion: true,
                activeInterval: 1.0 / 45.0
            )
        )
        let activeInterval = try XCTUnwrap(
            ContinuousAnimationPolicy.updateInterval(
                isActive: true,
                reducesMotion: false,
                activeInterval: 1.0 / 45.0
            )
        )
        XCTAssertEqual(activeInterval, 1.0 / 45.0, accuracy: 0.000_001)
    }

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
                cameraEnabled: false,
                fanControlEnabled: false
            )
        )
    }

    func testEachModuleUsesItsOwnMainFeatureToggle() {
        XCTAssertTrue(mainFeatureEnabled(.clipboard, enabledModule: .clipboard))
        XCTAssertTrue(mainFeatureEnabled(.shelf, enabledModule: .shelf))
        XCTAssertTrue(mainFeatureEnabled(.calendar, enabledModule: .calendar))
        XCTAssertTrue(mainFeatureEnabled(.camera, enabledModule: .camera))
        XCTAssertTrue(mainFeatureEnabled(.fanControl, enabledModule: .fanControl))

        XCTAssertFalse(mainFeatureEnabled(.clipboard, enabledModule: .shelf))
        XCTAssertFalse(mainFeatureEnabled(.shelf, enabledModule: .calendar))
        XCTAssertFalse(mainFeatureEnabled(.calendar, enabledModule: .camera))
        XCTAssertFalse(mainFeatureEnabled(.camera, enabledModule: .fanControl))
        XCTAssertFalse(mainFeatureEnabled(.fanControl, enabledModule: .clipboard))
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
            cameraEnabled: enabledModule == .camera,
            fanControlEnabled: enabledModule == .fanControl
        )
    }

    @MainActor
    func testFanControlSafeBoundsClamping() {
        let mock = MockTestSMCProvider(fanCount: 2, shouldFailWrite: false)
        let manager = FanControlManager(provider: mock)
        XCTAssertTrue(manager.isHardwareSupported)
        XCTAssertEqual(manager.fans.count, 2)

        manager.setTargetRPM(fanIndex: 0, rpm: 99999)
        XCTAssertEqual(manager.fans[0].targetRPM, 4500)

        manager.setTargetRPM(fanIndex: 0, rpm: 100)
        XCTAssertEqual(manager.fans[0].targetRPM, 1200)
    }

    @MainActor
    func testFanControlAutoFallbackWhenWriteFails() {
        let mock = MockTestSMCProvider(fanCount: 2, shouldFailWrite: true)
        let manager = FanControlManager(provider: mock)
        manager.setMode(manual: true)

        XCTAssertFalse(manager.isManualMode)
        XCTAssertFalse(manager.hasWritePermission)
        XCTAssertNotNil(manager.permissionNotice)
    }

    @MainActor
    func testFanControlUnsupportedHardwareHandling() {
        let mock = MockTestSMCProvider(fanCount: 0)
        let manager = FanControlManager(provider: mock)
        XCTAssertFalse(manager.isHardwareSupported)
        XCTAssertTrue(manager.fans.isEmpty)
    }

    private func cpuSamples(for processID: pid_t) throws -> [Double] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = [
            "-l", "3",
            "-s", "1",
            "-pid", String(processID),
            "-stats", "pid,cpu"
        ]

        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "anotherNotchTests", code: Int(process.terminationStatus))
        }

        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count == 2, fields[0] == String(processID) else { return nil }
                return Double(fields[1])
            }
    }

    private func launchApplication(at appURL: URL) throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["-onboardingCompleted", "YES"]
        configuration.createsNewApplicationInstance = true
        configuration.promptsUserIfNeeded = false

        let semaphore = DispatchSemaphore(value: 0)
        var launchedApplication: NSRunningApplication?
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { application, error in
            launchedApplication = application
            launchError = error
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            throw NSError(domain: "anotherNotchTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Timed out launching the Debug app."
            ])
        }
        if let launchError {
            throw launchError
        }
        return try XCTUnwrap(launchedApplication)
    }
}

private final class MockTestSMCProvider: SMCProvider {
    var isConnected: Bool = true
    var fans: [FanTelemetry] = []
    var shouldFailWrite: Bool = false

    init(fanCount: Int, shouldFailWrite: Bool = false) {
        self.shouldFailWrite = shouldFailWrite
        self.fans = (0..<fanCount).map { i in
            FanTelemetry(
                id: i,
                name: i == 0 ? "Left Fan" : "Right Fan",
                currentRPM: 1800,
                minRPM: 1200,
                maxRPM: 4500,
                targetRPM: 1800,
                isManual: false
            )
        }
    }

    func fanCount() -> Int {
        fans.count
    }

    func readFanTelemetry(index: Int) -> FanTelemetry? {
        guard index < fans.count else { return nil }
        return fans[index]
    }

    func writeFanMode(index: Int, manual: Bool) -> Bool {
        if shouldFailWrite { return false }
        guard index < fans.count else { return false }
        fans[index].isManual = manual
        return true
    }

    func writeFanTargetRPM(index: Int, rpm: Double) -> Bool {
        if shouldFailWrite { return false }
        guard index < fans.count else { return false }
        fans[index].targetRPM = rpm
        return true
    }
}
