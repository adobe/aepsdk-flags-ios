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

/// End-to-end `Flag.create` flows — criteria evaluation, metadata rebuild, poll refresh.
final class CombinedCDNFetchIntegrationTests: XCTestCase {

    private let edgeDomain = "e2e-service.test"
    private let clientId = "e2e-combined-client"
    private var session: URLSession!
    private var stub: MockFeatureServiceStub!

    private var edgeBaseUrl: String {
        FeatureServiceUrls.baseUrl(fromEdgeDomain: edgeDomain)
    }

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

    private func configuration() throws -> FlagConfiguration {
        try FlagConfiguration.builder()
            .edgeDomain(edgeDomain)
            .imsOrg("test-org")
            .sandboxName("test-sandbox")
            .clientId(clientId)
            .urlSession(session)
            .build()
    }

    private static let usOnlyCriteria =
        #"{"attr":"country","operator":"EQ","val":"US"}"#

    private static let e2eContextVersion = "e2e-context-v1"

    private func combinedBodyWithCountryCriteria(_ featureKey: String,
                                                 contextVersion: String = e2eContextVersion) -> String {
        FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroupWithFields(
                1001,
                "e2e-group",
                "\"criteria\":\"{\\\"criteria\\\":{\\\"attr\\\":\\\"country\\\",\\\"operator\\\":\\\"EQ\\\",\\\"val\\\":\\\"US\\\"}}\"",
                FeaturesResponseJsonFixtures.feature(1001, featureKey, "")),
            contextVersion: contextVersion,
            contexts: "[{\"id\":\"country\",\"type\":\"STRING\"}]")
    }

    private func featuresOnlyBodyWithCountryCriteria(_ featureKey: String) -> String {
        FeaturesResponseJsonFixtures.bodyFeaturesOnly(
            120,
            Self.e2eContextVersion,
            FeaturesResponseJsonFixtures.featureGroupWithFields(
                1001,
                "e2e-group",
                "\"criteria\":\"{\\\"criteria\\\":{\\\"attr\\\":\\\"country\\\",\\\"operator\\\":\\\"EQ\\\",\\\"val\\\":\\\"US\\\"}}\"",
                FeaturesResponseJsonFixtures.feature(1001, featureKey, "")))
    }

    private func body(featureName: String,
                      contextVersion: String = FeaturesResponseJsonFixtures.defaultContextVersion,
                      contexts: String = FeaturesResponseJsonFixtures.defaultContexts,
                      ttl: Int = 120) -> String {
        FeaturesResponseJsonFixtures.bodyWithSingleFeature(featureName,
                                                           ttl: ttl,
                                                           contextVersion: contextVersion,
                                                           contexts: contexts,
                                                           criteriaJson: Self.usOnlyCriteria)
    }

    private func registerStub(_ responses: MockFeatureServiceStub.Response...) {
        stub.enqueueList(Array(responses))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)
    }

    func testFlagCreateSingleFetchPopulatesCacheAndEvaluatesCriteria() throws {
        registerStub(.ok(body(featureName: "us-promo"), etag: "\"e2e-init\""))

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        XCTAssertTrue(flag.isInitialized)
        XCTAssertEqual(stub.requestCount, 1)
        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!, clientId: clientId, expectedContextVersion: nil)

        let usRequest = GetFeatureRequest.builder()
            .context(["country": ["US"]])
            .build()
        let ukRequest = GetFeatureRequest.builder()
            .context(["country": ["UK"]])
            .build()

        XCTAssertTrue(try flag.isFeatureEnabled("us-promo", for: usRequest))
        XCTAssertFalse(try flag.isFeatureEnabled("us-promo", for: ukRequest))

        XCTAssertTrue(flag.testClientCacheForUnitTests.hasMetadata())
        XCTAssertEqual(flag.testClientCacheForUnitTests.getMetadata()?.fieldDataTypeCache["country"], "STRING")
    }

    func testFlagCreateBuildsFilterServiceFromEmbeddedContexts() throws {
        registerStub(
            .ok(body(featureName: "segment-gate",
                     contexts: "[{\"id\":\"country\",\"type\":\"STRING\"},{\"id\":\"tier\",\"type\":\"STRING\"}]"),
                 etag: "\"e2e-fs\"")
        )

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        let premiumUS = GetFeatureRequest.builder()
            .context(["country": ["US"], "tier": ["premium"]])
            .build()

        let result = try flag.getFeature(named: "segment-gate", for: premiumUS)
        XCTAssertNotNil(result)
    }

    func testFlagRefreshPreservesEvaluationResults() throws {
        registerStub(.ok(body(featureName: "cached-flag"), etag: "\"stable-e2e\""))

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        let request = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        XCTAssertTrue(try flag.isFeatureEnabled("cached-flag", for: request))

        try flag.refreshCache()
        flag.cacheManager.testDrainWorkQueue()

        XCTAssertTrue(try flag.isFeatureEnabled("cached-flag", for: request))
        XCTAssertEqual(stub.requestCount, 2)
        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: FeaturesResponseJsonFixtures.defaultContextVersion,
                                                      expectedIfNoneMatch: "\"stable-e2e\"")
    }

    func testFlagRefreshNewFeaturesSameContextVersion() throws {
        registerStub(
            .ok(body(featureName: "promo-v1"), etag: "\"r1\""),
            .ok(body(featureName: "promo-v2"), etag: "\"r2\"")
        )

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        let request = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        XCTAssertTrue(try flag.isFeatureEnabled("promo-v1", for: request))

        try flag.refreshCache()
        flag.cacheManager.testDrainWorkQueue()

        XCTAssertFalse(try flag.isFeatureEnabled("promo-v1", for: request))
        XCTAssertTrue(try flag.isFeatureEnabled("promo-v2", for: request))
        XCTAssertEqual(flag.testClientCacheForUnitTests.getMetadata()?.contextVersion,
                       FeaturesResponseJsonFixtures.defaultContextVersion)
    }

    func testFlagRefreshNewContextVersionUpdatesFeaturesAndMetadata() throws {
        let initContexts = "[{\"id\":\"country\",\"type\":\"STRING\"}]"
        let pollContexts = "[{\"id\":\"country\",\"type\":\"STRING\"},{\"id\":\"tier\",\"type\":\"INTEGER\"}]"
        let usOnlyCriteria = #"{"attr":"country","operator":"EQ","val":"US"}"#
        let usPremiumCriteria =
            #"{"and":[{"attr":"country","operator":"EQ","val":"US"},{"attr":"tier","operator":"GT","val":2}]}"#

        registerStub(
            .ok(FeaturesResponseJsonFixtures.bodyWithSingleFeature("tier-gate",
                                                                    contextVersion: "ctx-e2e-v1",
                                                                    contexts: initContexts,
                                                                    criteriaJson: usOnlyCriteria),
                 etag: "\"m1\""),
            .ok(FeaturesResponseJsonFixtures.bodyWithSingleFeature("tier-gate",
                                                                    contextVersion: "ctx-e2e-v2",
                                                                    contexts: pollContexts,
                                                                    criteriaJson: usPremiumCriteria),
                 etag: "\"m2\"")
        )

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        let lowTier = GetFeatureRequest.builder()
            .context(["country": ["US"], "tier": ["1"]])
            .build()
        let highTier = GetFeatureRequest.builder()
            .context(["country": ["US"], "tier": ["5"]])
            .build()

        XCTAssertTrue(try flag.isFeatureEnabled("tier-gate", for: lowTier))

        try flag.refreshCache()
        flag.cacheManager.testDrainWorkQueue()

        XCTAssertEqual(flag.testClientCacheForUnitTests.getMetadata()?.contextVersion, "ctx-e2e-v2")
        XCTAssertEqual(flag.testClientCacheForUnitTests.getMetadata()?.fieldDataTypeCache["tier"], "INTEGER")
        XCTAssertFalse(try flag.isFeatureEnabled("tier-gate", for: lowTier))
        XCTAssertTrue(try flag.isFeatureEnabled("tier-gate", for: highTier))
    }

    func testFlagRefreshPositiveTtlReflectedInCacheManager() throws {
        registerStub(.ok(FeaturesResponseJsonFixtures.bodyWithTtlOnly(90), etag: "\"ttl-e2e\""))

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        XCTAssertEqual(flag.cacheManager.testResponsePollIntervalSeconds, 90)
    }

    func testFlagRefresh304LeavesEvaluationUnchanged() throws {
        registerStub(
            .ok(combinedBodyWithCountryCriteria("unchanged-feature"), etag: "\"e2e-etag-1\""),
            .notModified(etag: "\"e2e-etag-unchanged\"")
        )

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        let usRequest = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        let ukRequest = GetFeatureRequest.builder().context(["country": ["UK"]]).build()

        XCTAssertTrue(try flag.isFeatureEnabled("unchanged-feature", for: usRequest))
        XCTAssertFalse(try flag.isFeatureEnabled("unchanged-feature", for: ukRequest))

        try flag.refreshCache()
        flag.cacheManager.testDrainWorkQueue()

        XCTAssertEqual(stub.requestCount, 2)
        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: Self.e2eContextVersion,
                                                      expectedIfNoneMatch: "\"e2e-etag-1\"")
        XCTAssertTrue(try flag.isFeatureEnabled("unchanged-feature", for: usRequest))
        XCTAssertFalse(try flag.isFeatureEnabled("unchanged-feature", for: ukRequest))
        XCTAssertNotNil(try flag.getFeature(named: "unchanged-feature", for: usRequest))
    }

    func testFlagFeaturesOnlyRefreshReplacesFeaturesRetainsCriteriaSchema() throws {
        registerStub(
            .ok(combinedBodyWithCountryCriteria("country-gated-feature"), etag: "\"e2e-etag-1\""),
            .ok(featuresOnlyBodyWithCountryCriteria("delta-feature"), etag: "\"e2e-etag-2\"")
        )

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        let usRequest = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        let ukRequest = GetFeatureRequest.builder().context(["country": ["UK"]]).build()

        XCTAssertTrue(try flag.isFeatureEnabled("country-gated-feature", for: usRequest))
        XCTAssertFalse(try flag.isFeatureEnabled("country-gated-feature", for: ukRequest))

        try flag.refreshCache()
        flag.cacheManager.testDrainWorkQueue()

        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: Self.e2eContextVersion,
                                                      expectedIfNoneMatch: "\"e2e-etag-1\"")
        XCTAssertNil(try flag.getFeature(named: "country-gated-feature", for: usRequest))
        XCTAssertTrue(try flag.isFeatureEnabled("delta-feature", for: usRequest))
        XCTAssertFalse(try flag.isFeatureEnabled("delta-feature", for: ukRequest))
    }

    func testFlagCreateFailsWhenInitHttpFails() {
        var failures: [MockFeatureServiceStub.Response] = []
        for _ in 0..<FlagConstants.Cache.DEFAULT_MAX_RETRY_ATTEMPTS {
            failures.append(.init(statusCode: 500, body: nil, etag: "\"err\""))
        }
        stub.enqueueList(failures)
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        XCTAssertThrowsError(try Flag.create(configuration: configuration())) { error in
            guard let initError = error as? FlagInitError,
                  case .initializationFailed(let message, _) = initError else {
                return XCTFail("Expected FlagInitError.initializationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("Failed to initialize"))
        }
        XCTAssertEqual(stub.requestCount, FlagConstants.Cache.DEFAULT_MAX_RETRY_ATTEMPTS)
    }

    func testFlagCreateSucceedsAfterTransientFailures() throws {
        registerStub(
            .init(statusCode: 503, body: nil, etag: "\"e1\""),
            .init(statusCode: 503, body: nil, etag: "\"e2\""),
            .ok(FeaturesResponseJsonFixtures.minimalFGXBody(), etag: "\"recover-etag\"")
        )

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        XCTAssertNotNil(try flag.getFeature(named: "my-feature", for: GetFeatureRequest.defaultRequest))
        XCTAssertEqual(stub.requestCount, 3)
    }

    func testFlagRefreshFailureKeepsStaleSnapshot() throws {
        registerStub(
            .ok(combinedBodyWithCountryCriteria("stable-feature"), etag: "\"stable-etag\""),
            .init(statusCode: 500, body: nil, etag: "\"err\"")
        )

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        let usRequest = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        XCTAssertTrue(try flag.isFeatureEnabled("stable-feature", for: usRequest))

        try flag.refreshCache()
        flag.cacheManager.testDrainWorkQueue()

        XCTAssertTrue(try flag.isFeatureEnabled("stable-feature", for: usRequest))
    }

    func testNeverRequestsMetadataEndpoint() throws {
        registerStub(.ok(FeaturesResponseJsonFixtures.minimalFGXBody(), etag: "\"guard-etag\""))

        let flag = try Flag.create(configuration: configuration())
        defer { flag.close() }

        XCTAssertEqual(stub.requestCount, 1)
        XCTAssertFalse(stub.requestedPaths.contains { $0.lowercased().contains("metadata") })
        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!, clientId: clientId, expectedContextVersion: nil)
    }
}
