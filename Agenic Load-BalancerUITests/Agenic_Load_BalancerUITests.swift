//
//  Agenic_Load_BalancerUITests.swift
//  Agenic Load-BalancerUITests
//
//  Created by Zinco Verde on 5/5/26.
//

import AppKit
import XCTest

final class Agenic_Load_BalancerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testExample() throws {
        launchAgenic()
        XCTAssertTrue(element("Screen.Dashboard").waitForExistence(timeout: 8))
    }

    @MainActor
    func testSprintGPromptRouterCommandBarAndSettingsAtMinimumWindow() throws {
        launchAgenic()

        tap(identifier: "Toolbar.CommandBar")
        XCTAssertTrue(element("CommandBar.Title").waitForExistence(timeout: 5))
        XCTAssertTrue(element("CommandBar.Input").waitForExistence(timeout: 5))
        attachScreenshot(named: "command-bar-minimum-window")

        tap(identifier: "CommandBar.FooterClose")
        XCTAssertTrue(element("CommandBar.Title").waitForNonExistence(timeout: 5))

        tap(identifier: "Sidebar.promptRouter")
        XCTAssertTrue(element("Screen.PromptRouter").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Routing Rationale"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Approved Command Preview"].waitForExistence(timeout: 5))
        attachScreenshot(named: "prompt-router-minimum-window")

        tap(identifier: "Toolbar.Settings")
        XCTAssertTrue(element("Sheet.Settings").waitForExistence(timeout: 5))
        tap(identifier: "Settings.Tab.tools")
        XCTAssertTrue(app.staticTexts["Default Tool Permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("Settings.Toggle.allowToolCalling").waitForExistence(timeout: 5))
        XCTAssertTrue(element("Settings.Toggle.allowFilesystemWrites").waitForExistence(timeout: 5))
        attachScreenshot(named: "settings-tools-minimum-window")

        tap(identifier: "Settings.BackToApp")
        XCTAssertTrue(element("Sheet.Settings").waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testSprintGWorkspaceTaskRestoreAndAutonomyVisualFlow() throws {
        launchAgenic()

        expandProjectsDisclosure()
        tap(identifier: "Sidebar.ManageWorkspaces")
        XCTAssertTrue(element("Screen.Projects").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["IntegrityEvaluator"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("ProjectRow.uitest-integrity-evaluator.Settings").waitForExistence(timeout: 5))
        XCTAssertTrue(element("ProjectRow.uitest-integrity-evaluator.Delete").waitForExistence(timeout: 5))
        attachScreenshot(named: "projects-workspace-controls")

        tap(identifier: "ProjectRow.uitest-integrity-evaluator.Settings")
        XCTAssertTrue(element("Sheet.ProjectSettings").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Execution"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tool Permissions"].waitForExistence(timeout: 5))
        attachScreenshot(named: "project-settings-policy")
        tap(label: "Cancel")
        XCTAssertTrue(element("Sheet.ProjectSettings").waitForNonExistence(timeout: 5))

        expandWorkspace(projectID: "uitest-integrity-evaluator")
        tap(identifier: "Sidebar.WorkspaceRoot.uitest-integrity-evaluator")
        XCTAssertTrue(app.staticTexts["Workspace Paths"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tasks"].waitForExistence(timeout: 5))
        attachScreenshot(named: "workspace-task-summary")

        tap(identifier: "Sidebar.Task.coordination:uitest-coordination-active")
        XCTAssertTrue(app.staticTexts["Visual regression pass"].waitForExistence(timeout: 5))
        attachScreenshot(named: "workspace-task-detail")

        tap(identifier: "Sidebar.restoreCenter")
        XCTAssertTrue(element("Screen.Restore").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Restore Center"].waitForExistence(timeout: 5))
        attachScreenshot(named: "restore-center")

        tap(identifier: "Sidebar.autonomy")
        XCTAssertTrue(element("Screen.Autonomy").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Autonomy"].waitForExistence(timeout: 5))
        attachScreenshot(named: "autonomy-readiness")
    }

    @MainActor
    func testSprintLVisualRegressionSnapshotMatrix() throws {
        launchAgenic()
        try assertVisualSnapshot(named: "dashboard-default", baseline: .dashboard)

        tap(identifier: "Sidebar.promptRouter")
        XCTAssertTrue(element("Screen.PromptRouter").waitForExistence(timeout: 5))
        assertVisibleWithinWindow(identifier: "Screen.PromptRouter")
        try assertVisualSnapshot(named: "prompt-router-responsive", baseline: .contentDense)

        tap(identifier: "Toolbar.Settings")
        XCTAssertTrue(element("Sheet.Settings").waitForExistence(timeout: 5))
        tap(identifier: "Settings.Tab.tools")
        XCTAssertTrue(element("Settings.Toggle.allowToolCalling").waitForExistence(timeout: 5))
        assertVisibleWithinWindow(identifier: "Settings.Toggle.allowToolCalling")
        assertVisibleWithinWindow(identifier: "Settings.Toggle.allowFilesystemWrites")
        try assertVisualSnapshot(named: "settings-tools-alignment", baseline: .settingsSheet)
        tap(identifier: "Settings.BackToApp")
        XCTAssertTrue(element("Sheet.Settings").waitForNonExistence(timeout: 5))

        expandProjectsDisclosure()
        tap(identifier: "Sidebar.ManageWorkspaces")
        XCTAssertTrue(element("Screen.Projects").waitForExistence(timeout: 5))
        assertVisibleWithinWindow(identifier: "ProjectRow.uitest-integrity-evaluator.Settings")
        assertVisibleWithinWindow(identifier: "ProjectRow.uitest-integrity-evaluator.Delete")
        try assertVisualSnapshot(named: "projects-workspace-controls", baseline: .contentDense)

        tap(identifier: "Sidebar.conflictCenter")
        XCTAssertTrue(element("Screen.Conflicts").waitForExistence(timeout: 5))
        assertVisibleWithinWindow(identifier: "Conflicts.RunDrillButton")
        try assertVisualSnapshot(named: "conflict-center-drill-ready", baseline: .contentDense)
    }

    @MainActor
    func testSprintNExpandedVisualRegressionSnapshotMatrix() throws {
        launchAgenic()

        tap(identifier: "Toolbar.CommandBar")
        XCTAssertTrue(element("CommandBar.Title").waitForExistence(timeout: 5))
        assertVisibleWithinWindow(identifier: "CommandBar.Input")
        try assertVisualSnapshot(named: "command-bar-overlay", baseline: .settingsSheet)
        tap(identifier: "CommandBar.FooterClose")
        XCTAssertTrue(element("CommandBar.Title").waitForNonExistence(timeout: 5))

        tap(identifier: "Sidebar.providers")
        XCTAssertTrue(element("Screen.Providers").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "providers-catalog", baseline: .contentDense)

        expandProjectsDisclosure()
        tap(identifier: "Sidebar.ManageWorkspaces")
        XCTAssertTrue(element("Screen.Projects").waitForExistence(timeout: 5))
        tap(identifier: "ProjectRow.uitest-integrity-evaluator.Settings")
        XCTAssertTrue(element("Sheet.ProjectSettings").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "project-settings-policy", baseline: .settingsSheet)
        tap(label: "Cancel")
        XCTAssertTrue(element("Sheet.ProjectSettings").waitForNonExistence(timeout: 5))

        expandWorkspace(projectID: "uitest-integrity-evaluator")
        tap(identifier: "Sidebar.WorkspaceRoot.uitest-integrity-evaluator")
        XCTAssertTrue(element("Screen.Workspace.uitest-integrity-evaluator").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "workspace-task-tree", baseline: .contentDense)

        tap(identifier: "Sidebar.Task.coordination:uitest-coordination-active")
        XCTAssertTrue(element("Screen.WorkspaceTask.coordination:uitest-coordination-active").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "workspace-task-detail", baseline: .contentDense)

        tap(identifier: "Sidebar.restoreCenter")
        XCTAssertTrue(element("Screen.Restore").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "restore-center", baseline: .contentDense)

        tap(identifier: "Sidebar.autonomy")
        XCTAssertTrue(element("Screen.Autonomy").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "autonomy-control-room", baseline: .contentDense)

        tap(identifier: "Sidebar.history")
        XCTAssertTrue(element("Screen.History").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "history-ledger", baseline: .contentDense)

        tap(identifier: "Sidebar.agentNotes")
        XCTAssertTrue(element("Screen.AgentNotes").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "agentnotes-reconciliation", baseline: .contentDense)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting"]
            app.launch()
        }
    }

    // MARK: Sprint O.2 expanded matrices

    @MainActor
    func testSprintOMaximizedWindowSnapshotMatrix() throws {
        launchAgenic(extraArguments: ["--ui-maximize"])
        try assertVisualSnapshot(named: "dashboard-maximized", baseline: .maximized)

        tap(identifier: "Sidebar.promptRouter")
        XCTAssertTrue(element("Screen.PromptRouter").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "prompt-router-maximized", baseline: .maximized)

        tap(identifier: "Sidebar.history")
        XCTAssertTrue(element("Screen.History").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "history-maximized", baseline: .maximized)
    }

    @MainActor
    func testSprintODarkAppearanceSnapshotMatrix() throws {
        launchAgenic(extraArguments: ["--ui-appearance", "dark"])
        try assertVisualSnapshot(named: "dashboard-dark", baseline: .contentDense)

        tap(identifier: "Sidebar.promptRouter")
        XCTAssertTrue(element("Screen.PromptRouter").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "prompt-router-dark", baseline: .contentDense)

        tap(identifier: "Toolbar.Settings")
        XCTAssertTrue(element("Sheet.Settings").waitForExistence(timeout: 5))
        tap(identifier: "Settings.Tab.tools")
        XCTAssertTrue(element("Settings.Toggle.allowToolCalling").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "settings-tools-dark", baseline: .settingsSheet)
        tap(identifier: "Settings.BackToApp")
        XCTAssertTrue(element("Sheet.Settings").waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testSprintOLightAppearanceSnapshotMatrix() throws {
        launchAgenic(extraArguments: ["--ui-appearance", "light"])
        try assertVisualSnapshot(named: "dashboard-light", baseline: .contentDense)

        tap(identifier: "Sidebar.promptRouter")
        XCTAssertTrue(element("Screen.PromptRouter").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "prompt-router-light", baseline: .contentDense)

        tap(identifier: "Toolbar.Settings")
        XCTAssertTrue(element("Sheet.Settings").waitForExistence(timeout: 5))
        tap(identifier: "Settings.Tab.tools")
        XCTAssertTrue(element("Settings.Toggle.allowToolCalling").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "settings-tools-light", baseline: .settingsSheet)
        tap(identifier: "Settings.BackToApp")
        XCTAssertTrue(element("Sheet.Settings").waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testSprintOProviderSetupEdgeCaseSnapshotMatrix() throws {
        launchAgenic(extraArguments: ["--ui-provider-edge-cases"])
        tap(identifier: "Sidebar.providers")
        XCTAssertTrue(element("Screen.Providers").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "providers-edge-cases", baseline: .contentDense)
    }

    @MainActor
    func testSprintORunSheetSuccessFailureSnapshotMatrix() throws {
        launchAgenic(extraArguments: ["--ui-provider-edge-cases"])
        tap(identifier: "Sidebar.history")
        XCTAssertTrue(element("Screen.History").waitForExistence(timeout: 5))
        try assertVisualSnapshot(named: "history-success-and-failure", baseline: .contentDense)
    }

    // MARK: Sprint Q.2 remediation and recovery matrices

    @MainActor
    func testSprintQ2RemediationVisualRegressionSnapshotMatrix() throws {
        launchAgenic(extraArguments: ["--ui-provider-edge-cases", "--ui-foundation-diagnostics-fixture"])

        tap(identifier: "Sidebar.providers")
        XCTAssertTrue(element("Screen.Providers").waitForExistence(timeout: 5))
        XCTAssertTrue(element("ProviderRow.openai.codex.Reprobe").waitForExistence(timeout: 5))
        assertVisibleWithinWindow(identifier: "ProviderRow.openai.codex.Reprobe")
        try assertVisualSnapshot(named: "providers-remediation-actions", baseline: .contentDense)

        tap(identifier: "Sidebar.conflictCenter")
        XCTAssertTrue(element("Screen.Conflicts").waitForExistence(timeout: 5))
        tap(identifier: "Conflicts.RunDrillButton")
        assertLabel(
            identifier: "Conflicts.Status",
            contains: "Recovery drill",
            notContaining: ["failed", "needs review"]
        )
        try assertVisualSnapshot(named: "conflict-center-recovery-recorded", baseline: .contentDense)

        tap(identifier: "Sidebar.history")
        XCTAssertTrue(element("Screen.History").waitForExistence(timeout: 5))
        XCTAssertTrue(element("History.Continuation.UITEST-RUN-FAILED").waitForExistence(timeout: 5))
        assertVisibleWithinWindow(identifier: "History.Continuation.UITEST-RUN-FAILED")
        try assertVisualSnapshot(named: "history-continuation-depth", baseline: .contentDense)

        tap(identifier: "Toolbar.Settings")
        XCTAssertTrue(element("Sheet.Settings").waitForExistence(timeout: 5))
        tap(identifier: "Settings.Tab.agents")
        XCTAssertTrue(element("Settings.FoundationDiagnostics.Section").waitForExistence(timeout: 5))
        assertLabel(identifier: "Settings.FoundationDiagnostics.Section", contains: "failed")
        try assertVisualSnapshot(named: "foundation-diagnostics-fixture", baseline: .settingsSheet)
        tap(identifier: "Settings.BackToApp")
        XCTAssertTrue(element("Sheet.Settings").waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func launchAgenic(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + extraArguments
        app.launch()
        app.activate()
        if !element("Screen.Dashboard").waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(element("Screen.Dashboard").waitForExistence(timeout: 8))
    }

    @MainActor
    private func expandProjectsDisclosure() {
        if element("Sidebar.ManageWorkspaces").waitForExistence(timeout: 1) {
            return
        }

        let disclosure = app.disclosureTriangles.firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5), "Missing Projects disclosure triangle")
        disclosure.click()
        XCTAssertTrue(element("Sidebar.ManageWorkspaces").waitForExistence(timeout: 5))
    }

    @MainActor
    private func expandWorkspace(projectID: String) {
        let rootID = "Sidebar.WorkspaceRoot.\(projectID)"
        if element(rootID).waitForExistence(timeout: 1) {
            return
        }

        tap(identifier: "Sidebar.Workspace.\(projectID)")
        XCTAssertTrue(element(rootID).waitForExistence(timeout: 5), "Missing workspace root for \(projectID)")
    }

    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func assertLabel(
        identifier: String,
        contains requiredText: String,
        notContaining rejectedText: [String] = [],
        timeout: TimeInterval = 5
    ) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing UI element: \(identifier)")

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let stateText = accessibilityText(for: target)
            if stateText.localizedCaseInsensitiveContains(requiredText),
               rejectedText.allSatisfy({ !stateText.localizedCaseInsensitiveContains($0) }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let stateText = accessibilityText(for: target)
        XCTFail("\(identifier) accessibility text did not match. Expected to contain '\(requiredText)' and avoid \(rejectedText); actual text: '\(stateText)'")
    }

    @MainActor
    private func accessibilityText(for target: XCUIElement) -> String {
        let value = (target.value as? String) ?? ""
        return [target.label, value]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @MainActor
    private func tap(identifier: String, timeout: TimeInterval = 5) {
        app.activate()
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing UI element: \(identifier)")
        target.click()
    }

    @MainActor
    private func tap(label: String, timeout: TimeInterval = 5) {
        app.activate()
        let button = app.buttons[label].firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.click()
            return
        }

        let staticText = app.staticTexts[label].firstMatch
        XCTAssertTrue(staticText.waitForExistence(timeout: timeout), "Missing UI label: \(label)")
        staticText.click()
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Sprint G - \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func assertVisibleWithinWindow(identifier: String) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing UI element: \(identifier)")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Missing app window")

        let frame = target.frame
        let visibleWindow = window.frame.insetBy(dx: 4, dy: 4)
        XCTAssertGreaterThan(frame.width, 1, "\(identifier) has no visible width")
        XCTAssertGreaterThan(frame.height, 1, "\(identifier) has no visible height")
        XCTAssertTrue(
            visibleWindow.intersects(frame),
            "\(identifier) is outside the visible window. frame=\(frame), window=\(visibleWindow)"
        )
    }

    @MainActor
    private func assertVisualSnapshot(named name: String, baseline: VisualSnapshotBaseline) throws {
        let screenshot = app.screenshot()
        let pngData = screenshot.pngRepresentation
        let metrics = try VisualSnapshotMetrics.make(from: pngData)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Sprint L visual - \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        attachVisualMetrics(named: name, metrics: metrics)
        writeVisualArtifactsIfPermitted(name: name, pngData: pngData, metrics: metrics)

        XCTAssertGreaterThanOrEqual(metrics.width, baseline.minimumWidth, "\(name) screenshot width regressed")
        XCTAssertGreaterThanOrEqual(metrics.height, baseline.minimumHeight, "\(name) screenshot height regressed")
        XCTAssertGreaterThanOrEqual(metrics.colorBuckets, baseline.minimumColorBuckets, "\(name) lost visual color/detail range")
        XCTAssertGreaterThanOrEqual(metrics.luminanceStandardDeviation, baseline.minimumLuminanceStandardDeviation, "\(name) looks too flat or blank")
        XCTAssertGreaterThanOrEqual(metrics.averageNeighborDelta, baseline.minimumAverageNeighborDelta, "\(name) lost structural contrast")
        XCTAssertGreaterThanOrEqual(metrics.meanLuminance, baseline.minimumMeanLuminance, "\(name) is too dark")
        XCTAssertLessThanOrEqual(metrics.meanLuminance, baseline.maximumMeanLuminance, "\(name) is too bright")
    }

    @MainActor
    private func attachVisualMetrics(named name: String, metrics: VisualSnapshotMetrics) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(metrics) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Sprint L metrics - \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func writeVisualArtifactsIfPermitted(
        name: String,
        pngData: Data,
        metrics: VisualSnapshotMetrics
    ) {
        let outputPath = visualSnapshotOutputPath()

        let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: directory.appendingPathComponent("\(name).png"))

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metrics)
            try data.write(to: directory.appendingPathComponent("\(name).json"))
        } catch {
            XCTContext.runActivity(named: "Visual artifact file export skipped for \(name)") { activity in
                let attachment = XCTAttachment(string: error.localizedDescription)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }

    private func visualSnapshotOutputPath() -> String {
        if let outputPath = ProcessInfo.processInfo.environment["ALB_VISUAL_SNAPSHOT_DIR"],
           !outputPath.isEmpty {
            return outputPath
        }

        let usbRoot = "/Volumes/USB256/Xcode_Projects_Storage"
        if FileManager.default.fileExists(atPath: usbRoot) {
            return "\(usbRoot)/Agenic_VisualRegression_Latest/VisualSnapshots"
        }

        return "\(NSTemporaryDirectory())Agenic_VisualRegression_Latest/VisualSnapshots"
    }
}

private struct VisualSnapshotBaseline {
    var minimumWidth: Int
    var minimumHeight: Int
    var minimumColorBuckets: Int
    var minimumLuminanceStandardDeviation: Double
    var minimumAverageNeighborDelta: Double
    var minimumMeanLuminance: Double
    var maximumMeanLuminance: Double

    static let dashboard = VisualSnapshotBaseline(
        minimumWidth: 900,
        minimumHeight: 600,
        minimumColorBuckets: 10,
        minimumLuminanceStandardDeviation: 0.025,
        minimumAverageNeighborDelta: 0.004,
        minimumMeanLuminance: 0.03,
        maximumMeanLuminance: 0.75
    )

    static let contentDense = VisualSnapshotBaseline(
        minimumWidth: 900,
        minimumHeight: 600,
        minimumColorBuckets: 12,
        minimumLuminanceStandardDeviation: 0.025,
        minimumAverageNeighborDelta: 0.004,
        minimumMeanLuminance: 0.03,
        maximumMeanLuminance: 0.75
    )

    static let settingsSheet = VisualSnapshotBaseline(
        minimumWidth: 900,
        minimumHeight: 600,
        minimumColorBuckets: 12,
        minimumLuminanceStandardDeviation: 0.025,
        minimumAverageNeighborDelta: 0.004,
        minimumMeanLuminance: 0.03,
        maximumMeanLuminance: 0.75
    )

    /// Sprint O.2: looser bound on mean luminance because a maximized
    /// window includes a lot of background chrome, but the width/height
    /// baseline is raised so we catch regressions where the window
    /// silently shrinks back to its idealWidth.
    static let maximized = VisualSnapshotBaseline(
        minimumWidth: 1_100,
        minimumHeight: 700,
        minimumColorBuckets: 12,
        minimumLuminanceStandardDeviation: 0.025,
        minimumAverageNeighborDelta: 0.004,
        minimumMeanLuminance: 0.02,
        maximumMeanLuminance: 0.9
    )
}

private struct VisualSnapshotMetrics: Codable {
    var width: Int
    var height: Int
    var sampledPixels: Int
    var colorBuckets: Int
    var meanLuminance: Double
    var luminanceStandardDeviation: Double
    var averageNeighborDelta: Double

    static func make(from pngData: Data) throws -> VisualSnapshotMetrics {
        guard let representation = NSBitmapImageRep(data: pngData) else {
            throw XCTSkip("Could not decode screenshot PNG for visual regression metrics.")
        }

        let width = representation.pixelsWide
        let height = representation.pixelsHigh
        let columns = 48
        let rows = 32
        var luminanceValues: [Double] = []
        var buckets = Set<String>()
        var neighborDeltaTotal = 0.0
        var neighborDeltaCount = 0
        var priorRow: [Double] = Array(repeating: 0, count: columns)

        for row in 0..<rows {
            var priorLuminance: Double?
            for column in 0..<columns {
                let x = min(width - 1, max(0, Int((Double(column) + 0.5) / Double(columns) * Double(width))))
                let y = min(height - 1, max(0, Int((Double(row) + 0.5) / Double(rows) * Double(height))))
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }

                let red = Double(color.redComponent)
                let green = Double(color.greenComponent)
                let blue = Double(color.blueComponent)
                let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                luminanceValues.append(luminance)
                buckets.insert("\(Int(red * 7))-\(Int(green * 7))-\(Int(blue * 7))")

                if let priorLuminance {
                    neighborDeltaTotal += abs(luminance - priorLuminance)
                    neighborDeltaCount += 1
                }
                if row > 0 {
                    neighborDeltaTotal += abs(luminance - priorRow[column])
                    neighborDeltaCount += 1
                }
                priorLuminance = luminance
                priorRow[column] = luminance
            }
        }

        guard !luminanceValues.isEmpty else {
            throw XCTSkip("Screenshot did not produce sampled pixels for visual regression metrics.")
        }

        let mean = luminanceValues.reduce(0, +) / Double(luminanceValues.count)
        let variance = luminanceValues
            .map { pow($0 - mean, 2) }
            .reduce(0, +) / Double(luminanceValues.count)
        let neighborDelta = neighborDeltaCount > 0 ? neighborDeltaTotal / Double(neighborDeltaCount) : 0

        return VisualSnapshotMetrics(
            width: width,
            height: height,
            sampledPixels: luminanceValues.count,
            colorBuckets: buckets.count,
            meanLuminance: mean,
            luminanceStandardDeviation: sqrt(variance),
            averageNeighborDelta: neighborDelta
        )
    }
}
