//
//  Agenic_Load_BalancerUITests.swift
//  Agenic Load-BalancerUITests
//
//  Created by Zinco Verde on 5/5/26.
//

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
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting"]
            app.launch()
        }
    }

    @MainActor
    private func launchAgenic() {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
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
}
