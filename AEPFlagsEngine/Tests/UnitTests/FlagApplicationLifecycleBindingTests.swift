/*
 Copyright 2026 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import XCTest
@testable import FlagsEngine

#if canImport(UIKit)
import UIKit

final class FlagApplicationLifecycleBindingTests: XCTestCase {

    private let edgeDomain = "lifecycle-bind.test"
    private var session: URLSession!
    private var stub: MockFeatureServiceStub!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        stub = MockFeatureServiceStub()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: cfg)
    }

    override func tearDown() {
        session.finishTasksAndInvalidate()
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func stubEdge(clientId: String) {
        stub.setFixedBody(FeaturesResponseJsonFixtures.bodyWithTtlOnly(300), etag: "\"f1\"")
        stub.register(edgeBaseUrl: FeatureServiceUrls.baseUrl(fromEdgeDomain: edgeDomain), clientId: clientId)
    }

    private func makeLiveFlag(clientId: String = "lifecycle-bind") throws -> Flag {
        stubEdge(clientId: clientId)
        let cfg = try FlagConfiguration.builder()
            .edgeDomain(edgeDomain)
            .imsOrg("test-org")
            .sandboxName("test-sandbox")
            .clientId(clientId)
            .urlSession(session)
            .build()
        return try Flag.create(configuration: cfg)
    }

    private func postOnMain(_ name: Notification.Name, center: NotificationCenter) {
        let exp = expectation(description: "post \(name.rawValue)")
        DispatchQueue.main.async {
            center.post(name: name, object: nil)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testSyntheticBackgroundNotificationPausesPolling() throws {
        let flag = try makeLiveFlag()
        defer { flag.close() }

        let nc = NotificationCenter()
        let binding = FlagApplicationLifecycleBinding(flag: flag, notificationCenter: nc)
        binding.start()

        postOnMain(UIApplication.didEnterBackgroundNotification, center: nc)
        flag.cacheManager.testDrainWorkQueue()
        XCTAssertTrue(flag.cacheManager.testIsPaused)

        stubEdge(clientId: "lifecycle-bind")
        postOnMain(UIApplication.willEnterForegroundNotification, center: nc)
        flag.cacheManager.testDrainWorkQueue()
        XCTAssertFalse(flag.cacheManager.testIsPaused)

        binding.stop()
    }

    func testBindApplicationLifecycleUsesInjectedNotificationCenter() throws {
        let flag = try makeLiveFlag(clientId: "lifecycle-bind-2")
        defer { flag.close() }

        let nc = NotificationCenter()
        let binding = flag.bindApplicationLifecycle(notificationCenter: nc)

        postOnMain(UIApplication.didEnterBackgroundNotification, center: nc)
        flag.cacheManager.testDrainWorkQueue()
        XCTAssertTrue(flag.cacheManager.testIsPaused)

        binding.stop()
    }

    func testStopPreventsFurtherForwarding() throws {
        let flag = try makeLiveFlag(clientId: "lifecycle-bind-3")
        defer { flag.close() }

        let nc = NotificationCenter()
        let binding = FlagApplicationLifecycleBinding(flag: flag, notificationCenter: nc)
        binding.start()

        postOnMain(UIApplication.didEnterBackgroundNotification, center: nc)
        flag.cacheManager.testDrainWorkQueue()
        XCTAssertTrue(flag.cacheManager.testIsPaused)

        binding.stop()

        stubEdge(clientId: "lifecycle-bind-3")
        postOnMain(UIApplication.willEnterForegroundNotification, center: nc)
        flag.cacheManager.testDrainWorkQueue()
        XCTAssertTrue(flag.cacheManager.testIsPaused, "Observer removed; foreground should not unpause")
    }

    func testBindingDoesNotCrashWhenFlagNotInitialized() {
        let cfg = try! FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("o")
            .sandboxName("s")
            .clientId("c")
            .build()
        let flag = Flag(configuration: cfg)
        defer { flag.close() }

        let nc = NotificationCenter()
        let binding = FlagApplicationLifecycleBinding(flag: flag, notificationCenter: nc)
        binding.start()
        postOnMain(UIApplication.didEnterBackgroundNotification, center: nc)
        binding.stop()
    }
}

#else

/// `swift test` on macOS does not load UIKit; binding coverage runs on iOS hosts only.
final class FlagApplicationLifecycleBindingTests: XCTestCase {
    func testLifecycleBindingRequiresUIKitHost() {
        XCTAssertTrue(true)
    }
}
#endif
