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

final class SDKCacheManagerPollIntervalTests: XCTestCase {

    private let edgeBaseUrl = "http://poll-mock.test"
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

    private func stubFeatures(body: String) {
        MockURLProtocol.register(prefix: edgeBaseUrl + FlagConstants.FLAGS_FEATURE_PATH) { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [FlagConstants.Headers.ETAG: "\"etag-ttl\""])!
            return (resp, body.data(using: .utf8))
        }
    }

    private func proxy() -> APIProxy {
        APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: session)
    }

    func testNonPositiveTtlFallsBackToDefaultPollInterval() throws {
        for ttl in [0, -1, -120] {
            MockURLProtocol.reset()
            let cfg = URLSessionConfiguration.ephemeral
            cfg.protocolClasses = [MockURLProtocol.self]
            session = URLSession(configuration: cfg)
            stubFeatures(body: FeaturesResponseJsonFixtures.bodyWithTtlOnly(ttl))
            let mgr = SDKCacheManager(policyCache: PolicyCache())
            defer { mgr.shutdown() }
            try mgr.configure(clientId: "test-client", apiProxy: proxy())
            mgr.testDrainWorkQueue()
            XCTAssertEqual(mgr.testResponsePollIntervalSeconds, FlagConstants.Cache.DEFAULT_POLL_INTERVAL_SECONDS)
            XCTAssertTrue(mgr.testIsInitialized)
        }
    }

    func testApiProxyReturnsNullPollIntervalForZeroTtl() throws {
        stubFeatures(body: FeaturesResponseJsonFixtures.bodyWithTtlOnly(0))
        let resp = try proxy().getFeatures(clientId: "test-client", contextVersion: nil, etag: nil)
        XCTAssertNil(resp.pollInterval)
    }

    func testApiProxyReturnsNullPollIntervalForNegativeTtl() throws {
        stubFeatures(body: FeaturesResponseJsonFixtures.bodyWithTtlOnly(-60))
        let resp = try proxy().getFeatures(clientId: "test-client", contextVersion: nil, etag: nil)
        XCTAssertNil(resp.pollInterval)
    }

    func testPositiveTtlFromCombinedResponseSetsPollInterval() throws {
        stubFeatures(body: FeaturesResponseJsonFixtures.bodyWithTtlOnly(180))
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }
        try mgr.configure(clientId: "test-client", apiProxy: proxy())
        mgr.testDrainWorkQueue()
        XCTAssertEqual(mgr.testResponsePollIntervalSeconds, 180)
    }
}
