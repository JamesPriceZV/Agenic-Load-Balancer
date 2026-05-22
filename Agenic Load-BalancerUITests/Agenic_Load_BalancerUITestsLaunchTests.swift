//
//  Agenic_Load_BalancerUITestsLaunchTests.swift
//  Agenic Load-BalancerUITests
//
//  Created by Zinco Verde on 5/5/26.
//

import XCTest

final class Agenic_Load_BalancerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.activate()

        let dashboard = app.descendants(matching: .any)
            .matching(identifier: "Screen.Dashboard")
            .firstMatch
        if !dashboard.waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(dashboard.waitForExistence(timeout: 8))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
