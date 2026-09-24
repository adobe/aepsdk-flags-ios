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

/// Failure-path tests for ``SDKCacheManager`` HTTP fetch and retry behavior.
final class SDKCacheManagerFailureTests: XCTestCase {

    private let clientId = "fail-client"
    private let edgeBaseUrl = "http://cache-failure.test"
    private let imsOrg = "test-org"
    private let sandboxName = "test-sandbox"
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

    private func proxy() -> APIProxy {
        APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: session)
    }

    private func combinedBody(contextVersion: String, featureKey: String) -> String {
        FeaturesResponseJsonFixtures.bodyWithSingleFeature(featureKey, contextVersion: contextVersion)
    }

    func testRefreshUnparseableBodyPreservesFeatureSnapshot() throws {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        stub.enqueue(.ok(combinedBody(contextVersion: "ctx-v1", featureKey: "feature-a"), etag: "\"etag-1\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        stub.enqueue(.ok("not json", etag: "\"etag-bad\""))
        mgr.refreshClientCache()
        mgr.testDrainWorkQueue()

        XCTAssertEqual(mgr.clientCache.getFeaturesEtag(clientId: clientId), "\"etag-1\"")
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-a"))
    }

    func testRefreshValidEmptyFeatureGroupsClearsSnapshot() throws {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        stub.enqueue(.ok(combinedBody(contextVersion: "ctx-v1", featureKey: "feature-a"), etag: "\"etag-1\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        let emptyBody = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(120, "", contextVersion: "ctx-v1")
        stub.enqueue(.ok(emptyBody, etag: "\"etag-empty\""))
        mgr.refreshClientCache()
        mgr.testDrainWorkQueue()

        XCTAssertEqual(mgr.clientCache.getFeaturesEtag(clientId: clientId), "\"etag-empty\"")
        XCTAssertTrue(mgr.clientCache.getFeatures(clientId: clientId)?.isEmpty ?? false)
    }

    func testConfigureFailsAfterRetries() {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        for _ in 0..<FlagConstants.Cache.DEFAULT_MAX_RETRY_ATTEMPTS {
            stub.enqueue(.init(statusCode: 500, body: nil, etag: "\"err\""))
        }
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        XCTAssertThrowsError(try mgr.configure(clientId: clientId, apiProxy: proxy())) { error in
            guard let initError = error as? FlagInitError,
                  case .initializationFailed(let message, _) = initError else {
                XCTFail("expected FlagInitError.initializationFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "Failed to initialize cache manager")
        }
        XCTAssertEqual(stub.requestCount, FlagConstants.Cache.DEFAULT_MAX_RETRY_ATTEMPTS)
    }

    func testConfigureRecoversOnLaterRetry() throws {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        stub.enqueue(
            .init(statusCode: 502, body: nil, etag: "\"e1\""),
            .init(statusCode: 502, body: nil, etag: "\"e2\""),
            .ok(combinedBody(contextVersion: "ctx-v1", featureKey: "feature-a"), etag: "\"etag-recover\"")
        )
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        XCTAssertEqual(stub.requestCount, 3)
        XCTAssertTrue(mgr.clientCache.hasFeatures(clientId: clientId))
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-a"))
    }

    func testRefreshFailurePreservesFeatureSnapshot() throws {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        stub.enqueue(.ok(combinedBody(contextVersion: "ctx-v1", featureKey: "feature-a"), etag: "\"etag-1\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        stub.enqueue(.init(statusCode: 500, body: nil, etag: "\"err\""))
        mgr.refreshClientCache()
        mgr.testDrainWorkQueue()

        XCTAssertEqual(mgr.clientCache.getFeaturesEtag(clientId: clientId), "\"etag-1\"")
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-a"))
    }

    func testRefreshFailurePreservesMetadataSnapshot() throws {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        stub.enqueue(.ok(combinedBody(contextVersion: "ctx-v1", featureKey: "feature-a"), etag: "\"etag-1\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        XCTAssertEqual(mgr.clientCache.getMetadata()?.contextVersion, "ctx-v1")

        stub.enqueue(.init(statusCode: 500, body: nil, etag: "\"err\""))
        mgr.refreshClientCache()
        mgr.testDrainWorkQueue()

        XCTAssertEqual(mgr.clientCache.getMetadata()?.contextVersion, "ctx-v1")
        XCTAssertEqual(mgr.clientCache.getMetadata()?.fieldDataTypeCache["country"], "STRING")
    }

    func testRefreshAfterFailureSendsCachedContextVersionAndEtag() throws {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        stub.enqueue(.ok(combinedBody(contextVersion: "ctx-v1", featureKey: "feature-a"), etag: "\"etag-1\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        stub.enqueue(.init(statusCode: 500, body: nil, etag: "\"err\""))
        mgr.refreshClientCache()
        mgr.testDrainWorkQueue()

        stub.enqueue(.ok(combinedBody(contextVersion: "ctx-v1", featureKey: "feature-b"), etag: "\"etag-2\""))
        mgr.refreshClientCache()
        mgr.testDrainWorkQueue()

        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: "ctx-v1",
                                                      expectedIfNoneMatch: "\"etag-1\"")
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-b"))
    }

    func testScheduledPollSurvivesUnparseableBodyAndRecovers() throws {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        defer { mgr.shutdown() }

        let initBody = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            1,
            FeaturesResponseJsonFixtures.singleFeatureGroup("feature-a", groupId: 1, featureId: 1),
            contextVersion: "ctx-v1")

        stub.enqueue(.ok(initBody, etag: "\"etag-1\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()
        XCTAssertEqual(stub.requestCount, 1)

        stub.append(
            .ok("not json", etag: "\"etag-bad\""),
            .ok(FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
                1,
                FeaturesResponseJsonFixtures.singleFeatureGroup("feature-b", groupId: 1, featureId: 2),
                contextVersion: "ctx-v1"),
                 etag: "\"etag-2\"")
        )

        mgr.testRunScheduledPoll()
        mgr.testDrainWorkQueue()

        XCTAssertEqual(mgr.clientCache.getFeaturesEtag(clientId: clientId), "\"etag-1\"")
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-a"))
        XCTAssertNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-b"))

        mgr.testRunScheduledPoll()
        mgr.testDrainWorkQueue()

        XCTAssertEqual(mgr.clientCache.getFeaturesEtag(clientId: clientId), "\"etag-2\"")
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-b"))
        XCTAssertNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-a"))
    }
}
