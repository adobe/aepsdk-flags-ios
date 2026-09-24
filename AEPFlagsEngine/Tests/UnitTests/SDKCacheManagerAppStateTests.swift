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

final class SDKCacheManagerAppStateTests: XCTestCase {

    private let edgeBaseUrl = "https://appstate-mock.test"
    private let imsOrg = "test-org"
    private let sandboxName = "test-sandbox"
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: cfg)
    }

    override func tearDown() {
        session.finishTasksAndInvalidate()
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func stubFeatures(body: String, requestCounter: UnsafeMutablePointer<Int>? = nil) {
        MockURLProtocol.register(prefix: edgeBaseUrl + FlagConstants.FLAGS_FEATURE_PATH) { req in
            requestCounter?.pointee += 1
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [FlagConstants.Headers.ETAG: "\"etag-1\""])!
            return (resp, body.data(using: .utf8))
        }
    }

    private func proxy() -> APIProxy {
        APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: session)
    }

    private func makeManager() -> SDKCacheManager {
        SDKCacheManager(policyCache: PolicyCache())
    }

    private func initialize(_ mgr: SDKCacheManager, body: String = FeaturesResponseJsonFixtures.emptyResponse, counter: UnsafeMutablePointer<Int>? = nil) throws {
        stubFeatures(body: body, requestCounter: counter)
        let proxy = proxy()
        try mgr.configure(clientId: "test-client", apiProxy: proxy)
        mgr.testDrainWorkQueue()
    }

    // MARK: - Before initialization

    func testBackgroundBeforeInitIsNoOp() {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()
        XCTAssertFalse(mgr.testIsInitialized)
    }

    func testForegroundBeforeInitIsNoOp() {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        mgr.onAppStateChanged(.foreground)
        mgr.testDrainWorkQueue()
        XCTAssertFalse(mgr.testIsInitialized)
    }

    func testNilStateBeforeInitIsNoOp() {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        mgr.onAppStateChanged(nil)
        mgr.testDrainWorkQueue()
        XCTAssertFalse(mgr.testIsInitialized)
    }

    // MARK: - Background

    func testBackgroundSetsPausedFlag() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)
        XCTAssertFalse(mgr.testIsPaused)

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()
        XCTAssertTrue(mgr.testIsPaused)
    }

    func testRepeatedBackgroundIsIdempotent() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)
        mgr.onAppStateChanged(.background)
        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()
        XCTAssertTrue(mgr.testIsPaused)
    }

    func testBackgroundCancelsScheduledPolling() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)
        let generationBefore = mgr.testPollGeneration

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()

        XCTAssertTrue(mgr.testIsPaused)
        XCTAssertGreaterThan(mgr.testPollGeneration, generationBefore)
    }

    func testNilStateAfterInitIsNoOp() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)
        mgr.onAppStateChanged(nil)
        mgr.testDrainWorkQueue()
        XCTAssertFalse(mgr.testIsPaused)
    }

    // MARK: - Foreground

    func testForegroundAfterBackgroundClearsPaused() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)
        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()
        XCTAssertTrue(mgr.testIsPaused)

        stubFeatures(body: FeaturesResponseJsonFixtures.emptyResponse)
        mgr.onAppStateChanged(.foreground)
        mgr.testDrainWorkQueue()
        XCTAssertFalse(mgr.testIsPaused)
    }

    func testForegroundAfterBackgroundRestartsPolling() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)
        let afterInit = mgr.testStartPollingInvocationCount
        XCTAssertGreaterThanOrEqual(afterInit, 1)

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()
        let afterBg = mgr.testStartPollingInvocationCount

        stubFeatures(body: FeaturesResponseJsonFixtures.emptyResponse)
        mgr.onAppStateChanged(.foreground)
        mgr.testDrainWorkQueue()

        XCTAssertGreaterThan(mgr.testStartPollingInvocationCount, afterBg, "startPolling should run again on foreground resume")
    }

    func testForegroundTriggersImmediateRefresh() throws {
        var counter = 0
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr, counter: &counter)
        let afterInit = counter

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()

        stubFeatures(body: FeaturesResponseJsonFixtures.emptyResponse, requestCounter: &counter)
        mgr.onAppStateChanged(.foreground)
        mgr.testDrainWorkQueue()

        XCTAssertGreaterThan(counter, afterInit, "Foreground resume should perform an HTTP refresh")
    }

    func testForegroundRefreshSendsCachedContextVersionAndEtag() throws {
        let initBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("fg-feature", contextVersion: "ctx-v1")
        let mgr = makeManager()
        defer { mgr.shutdown() }

        MockURLProtocol.register(prefix: edgeBaseUrl + FlagConstants.FLAGS_FEATURE_PATH) { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: [FlagConstants.Headers.ETAG: "\"etag-1\""])!
            return (resp, initBody.data(using: .utf8))
        }

        try mgr.configure(clientId: "test-client", apiProxy: proxy())
        mgr.testDrainWorkQueue()

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()

        MockURLProtocol.reset()
        var capturedRequest: URLRequest?
        MockURLProtocol.register(prefix: edgeBaseUrl + FlagConstants.FLAGS_FEATURE_PATH) { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: [FlagConstants.Headers.ETAG: "\"etag-fg-refresh\""])!
            let body = FeaturesResponseJsonFixtures.bodyWithTtlOnly(120, contextVersion: "ctx-v1")
            return (resp, body.data(using: .utf8))
        }

        mgr.onAppStateChanged(.foreground)
        mgr.testDrainWorkQueue()

        let refreshRequest = try XCTUnwrap(capturedRequest)
        ServiceRequestAssertions.assertFeatureRequest(refreshRequest,
                                                      clientId: "test-client",
                                                      expectedContextVersion: "ctx-v1",
                                                      expectedIfNoneMatch: "\"etag-1\"")
    }

    func testRepeatedForegroundIsIdempotent() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)
        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()

        stubFeatures(body: FeaturesResponseJsonFixtures.emptyResponse)
        mgr.onAppStateChanged(.foreground)
        mgr.onAppStateChanged(.foreground)
        mgr.testDrainWorkQueue()

        XCTAssertFalse(mgr.testIsPaused)
    }

    // MARK: - Round trip

    func testBackgroundForegroundBackgroundCycle() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()
        XCTAssertTrue(mgr.testIsPaused)

        stubFeatures(body: FeaturesResponseJsonFixtures.emptyResponse)
        mgr.onAppStateChanged(.foreground)
        mgr.testDrainWorkQueue()
        XCTAssertFalse(mgr.testIsPaused)

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()
        XCTAssertTrue(mgr.testIsPaused)
    }

    func testCacheIsPreservedThroughBackground() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try initialize(mgr)

        let featureGroup = FeaturesResponse()
        featureGroup.featureGroupName = "R-persist"
        featureGroup.features = ["persist-feature"]
        mgr.clientCache.putFeatures(clientId: "test-client", features: [featureGroup], etag: "etag-persist")

        mgr.onAppStateChanged(.background)
        mgr.testDrainWorkQueue()

        let entry = mgr.clientCache.getFeatures(clientId: "test-client")
        XCTAssertNotNil(entry)
        XCTAssertFalse(entry!.isEmpty)
        XCTAssertNotNil(entry!.findFeature("persist-feature"))
    }
}
