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

final class APIProxyTests: XCTestCase {

    private let edgeBaseUrl = "https://example.com"
    private let imsOrg = "test-org"
    private let sandboxName = "test-sandbox"

    private func makeProxy(sharedSession: URLSession? = nil) -> APIProxy {
        APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: sharedSession)
    }

    func testInternalClientCreatesURLSession() {
        let proxy = makeProxy()
        XCTAssertNotNil(proxy.urlSession)
        proxy.shutdown()
    }

    func testInternalClientUsesSdkTimeouts() {
        let proxy = makeProxy()
        defer { proxy.shutdown() }
        let cfg = proxy.urlSession.configuration
        XCTAssertEqual(proxy.sdkConnectTimeoutSeconds, FlagConstants.HTTP.CONNECT_TIMEOUT_SECONDS)
        XCTAssertEqual(proxy.sdkReadTimeoutSeconds, FlagConstants.HTTP.READ_TIMEOUT_SECONDS)
        XCTAssertEqual(proxy.sdkWriteTimeoutSeconds, FlagConstants.HTTP.WRITE_TIMEOUT_SECONDS)
        XCTAssertEqual(cfg.timeoutIntervalForRequest, FlagConstants.HTTP.READ_TIMEOUT_SECONDS)
        XCTAssertEqual(cfg.timeoutIntervalForResource, FlagConstants.HTTP.WRITE_TIMEOUT_SECONDS)
        XCTAssertTrue(proxy.ownsSession)
    }

    func testSharedModeUsesSameSessionInstance() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.timeoutIntervalForResource = 2
        let shared = URLSession(configuration: cfg)
        defer { shared.finishTasksAndInvalidate() }

        let proxy = makeProxy(sharedSession: shared)
        XCTAssertTrue(proxy.urlSession === shared)
        XCTAssertFalse(proxy.ownsSession)
        proxy.shutdown()
        XCTAssertNotNil(shared.configuration)
    }

    func testSharedSessionRetainsCallerTimeouts() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.timeoutIntervalForResource = 3
        let shared = URLSession(configuration: cfg)
        defer { shared.finishTasksAndInvalidate() }

        let proxy = makeProxy(sharedSession: shared)
        defer { proxy.shutdown() }

        XCTAssertEqual(shared.configuration.timeoutIntervalForRequest, 2)
        XCTAssertEqual(shared.configuration.timeoutIntervalForResource, 3)
    }

    func testShutdownDoesNotInvalidateSharedSession() {
        let shared = URLSession(configuration: .ephemeral)
        defer { shared.finishTasksAndInvalidate() }
        let proxy = makeProxy(sharedSession: shared)
        XCTAssertFalse(proxy.ownsSession)
        proxy.shutdown()
        XCTAssertTrue(proxy.urlSession === shared)
    }

    func testNullEdgeBaseUrlRejected() {
        XCTAssertFalse(APIProxy.isValidEdgeBaseUrl(nil))
    }

    func testBlankEdgeBaseUrlRejected() {
        XCTAssertFalse(APIProxy.isValidEdgeBaseUrl("   "))
    }

    func testTrailingSlashIsStripped() {
        let proxy = APIProxy(edgeBaseUrl: edgeBaseUrl + "/", imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: nil)
        defer { proxy.shutdown() }
        XCTAssertEqual(proxy.edgeBaseUrl, edgeBaseUrl)
    }
}
