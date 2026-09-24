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

/// Combined metadata and features fetch scenarios.
final class SDKCacheManagerCombinedFetchTests: XCTestCase {

    private let edgeBaseUrl = "http://combined-service.test"
    private let imsOrg = "test-org"
    private let sandboxName = "test-sandbox"
    private let clientId = "combined-client"
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

    private func makeManager(onMetadataUpdated: ((MetadataResponse) -> Void)? = nil) -> SDKCacheManager {
        let mgr = SDKCacheManager(policyCache: PolicyCache())
        mgr.onMetadataUpdated = onMetadataUpdated
        return mgr
    }

    private func proxy() -> APIProxy {
        APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: session)
    }

    private func configure(_ mgr: SDKCacheManager, stubBody: String, etag: String = "\"init-etag\"") throws {
        stub.setFixedBody(stubBody, etag: etag)
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()
    }

    private func refresh(_ mgr: SDKCacheManager) {
        mgr.refreshClientCache()
        mgr.testDrainWorkQueue()
    }

    func testInitUsesSingleCombinedFetchNoMetadataEndpoint() throws {
        let body = FeaturesResponseJsonFixtures.bodyWithSingleFeature("launch-banner")
        let mgr = makeManager()
        defer { mgr.shutdown() }

        try configure(mgr, stubBody: body)

        XCTAssertEqual(stub.requestCount, 1)
        XCTAssertEqual(stub.requestedPaths.first, FlagConstants.FLAGS_FEATURE_PATH)
        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!, clientId: clientId, expectedContextVersion: nil)
    }

    func testInitPopulatesFeaturesAndMetadataFromOneResponse() throws {
        let contexts = "[{\"id\":\"country\",\"type\":\"STRING\"},{\"id\":\"platform\",\"type\":\"STRING\"}]"
        let body = FeaturesResponseJsonFixtures.bodyWithSingleFeature("geo-gate",
                                                                      contextVersion: "ctx-init-v1",
                                                                      contexts: contexts)
        let mgr = makeManager()
        defer { mgr.shutdown() }

        try configure(mgr, stubBody: body)

        let features = mgr.clientCache.getFeatures(clientId: clientId)
        XCTAssertNotNil(features?.findFeature("geo-gate"))

        let metadata = mgr.clientCache.getMetadata()
        XCTAssertEqual(metadata?.contextVersion, "ctx-init-v1")
        XCTAssertEqual(metadata?.fieldDataTypeCache["country"], "STRING")
        XCTAssertEqual(metadata?.fieldDataTypeCache["platform"], "STRING")
    }

    func testInitInvokesOnMetadataUpdatedOnce() throws {
        var callbackCount = 0
        var lastVersion: String?
        let mgr = makeManager { metadata in
            callbackCount += 1
            lastVersion = metadata.contextVersion
        }
        defer { mgr.shutdown() }

        try configure(mgr,
                      stubBody: FeaturesResponseJsonFixtures.bodyWithSingleFeature("flag-a",
                                                                                   contextVersion: "ctx-callback-v1"))

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(lastVersion, "ctx-callback-v1")
    }

    func testRefreshSendsCachedContextVersionQueryParam() throws {
        let initBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("stable-flag",
                                                                          contextVersion: "ctx-stable")
        let pollBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("stable-flag-v2",
                                                                          contextVersion: "ctx-stable")
        stub.enqueue(.ok(initBody, etag: "\"etag-1\""), .ok(pollBody, etag: "\"etag-2\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        let mgr = makeManager()
        defer { mgr.shutdown() }
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        refresh(mgr)

        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: "ctx-stable",
                                                      expectedIfNoneMatch: "\"etag-1\"")
    }

    func testPoll304IsFullNoOp() throws {
        let initBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("feature-a",
                                                                          contextVersion: "ctx-v1")
        stub.enqueue(.ok(initBody, etag: "\"etag-1\""), .notModified(etag: "\"etag-unchanged\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        var metadataCallbacks = 0
        let mgr = makeManager { _ in metadataCallbacks += 1 }
        defer { mgr.shutdown() }
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        refresh(mgr)

        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: "ctx-v1",
                                                      expectedIfNoneMatch: "\"etag-1\"")
        XCTAssertEqual(mgr.clientCache.getFeaturesEtag(clientId: clientId), "\"etag-1\"")
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-a"))
        XCTAssertEqual(mgr.clientCache.getMetadata()?.contextVersion, "ctx-v1")
        XCTAssertEqual(metadataCallbacks, 1)
    }

    func testRefresh200NewFeaturesSameContextVersionUpdatesFeaturesOnly() throws {
        let sharedContextVersion = "ctx-shared-v1"
        let initBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("feature-v1",
                                                                          contextVersion: sharedContextVersion)
        let pollBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("feature-v2",
                                                                          contextVersion: sharedContextVersion)

        stub.enqueue(.ok(initBody, etag: "\"etag-v1\""), .ok(pollBody, etag: "\"etag-v2\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        var metadataCallbacks = 0
        let mgr = makeManager { _ in metadataCallbacks += 1 }
        defer { mgr.shutdown() }
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-v1"))
        XCTAssertEqual(metadataCallbacks, 1)

        refresh(mgr)

        XCTAssertNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-v1"))
        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("feature-v2"))
        XCTAssertEqual(mgr.clientCache.getMetadata()?.contextVersion, sharedContextVersion)
        XCTAssertEqual(metadataCallbacks, 1, "Same contextVersion must not re-trigger metadata callback")
    }

    func testRefresh200NewContextVersionUpdatesMetadataAndCallback() throws {
        let initContexts = "[{\"id\":\"country\",\"type\":\"STRING\"}]"
        let pollContexts = "[{\"id\":\"country\",\"type\":\"STRING\"},{\"id\":\"locale\",\"type\":\"STRING\"}]"
        let initBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("intl-flag",
                                                                          contextVersion: "ctx-v1",
                                                                          contexts: initContexts)
        let pollBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("intl-flag",
                                                                          contextVersion: "ctx-v2",
                                                                          contexts: pollContexts)

        stub.enqueue(.ok(initBody, etag: "\"etag-a\""), .ok(pollBody, etag: "\"etag-b\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        var versions: [String] = []
        let mgr = makeManager { metadata in
            if let v = metadata.contextVersion { versions.append(v) }
        }
        defer { mgr.shutdown() }
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        XCTAssertNil(mgr.clientCache.getMetadata()?.fieldDataTypeCache["locale"])

        refresh(mgr)

        XCTAssertEqual(mgr.clientCache.getMetadata()?.contextVersion, "ctx-v2")
        XCTAssertEqual(mgr.clientCache.getMetadata()?.fieldDataTypeCache["locale"], "STRING")
        XCTAssertEqual(versions, ["ctx-v1", "ctx-v2"])
    }

    func testRefresh200NewFeaturesAndContextVersionUpdatesBothTracks() throws {
        let initBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("rollout-a",
                                                                          contextVersion: "meta-a")
        let pollBody = FeaturesResponseJsonFixtures.bodyWithSingleFeature("rollout-b",
                                                                          contextVersion: "meta-b",
                                                                          contexts: "[{\"id\":\"tier\",\"type\":\"STRING\"}]")

        stub.enqueue(.ok(initBody, etag: "\"e1\""), .ok(pollBody, etag: "\"e2\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        let mgr = makeManager()
        defer { mgr.shutdown() }
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()

        refresh(mgr)

        XCTAssertNotNil(mgr.clientCache.getFeatures(clientId: clientId)?.findFeature("rollout-b"))
        XCTAssertEqual(mgr.clientCache.getMetadata()?.contextVersion, "meta-b")
        XCTAssertEqual(mgr.clientCache.getMetadata()?.fieldDataTypeCache["tier"], "STRING")
    }

    func testInitPositiveTtlSetsPollInterval() throws {
        let mgr = makeManager()
        defer { mgr.shutdown() }
        try configure(mgr, stubBody: FeaturesResponseJsonFixtures.bodyWithTtlOnly(180))
        XCTAssertEqual(mgr.testResponsePollIntervalSeconds, 180)
    }

    func testRefresh200NewTtlUpdatesPollInterval() throws {
        stub.enqueue(
            .ok(FeaturesResponseJsonFixtures.bodyWithTtlOnly(120), etag: "\"e1\""),
            .ok(FeaturesResponseJsonFixtures.bodyWithTtlOnly(300), etag: "\"e2\"")
        )
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        let mgr = makeManager()
        defer { mgr.shutdown() }
        try mgr.configure(clientId: clientId, apiProxy: proxy())
        mgr.testDrainWorkQueue()
        XCTAssertEqual(mgr.testResponsePollIntervalSeconds, 120)

        refresh(mgr)
        XCTAssertEqual(mgr.testResponsePollIntervalSeconds, 300)
    }
}
