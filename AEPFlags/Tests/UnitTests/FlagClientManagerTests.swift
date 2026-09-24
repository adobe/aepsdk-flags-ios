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

@testable import AEPFlags
@testable import AEPCore
import FlagsEngine
import XCTest

class FlagClientManagerTests: XCTestCase {
    private var runtime: TestableExtensionRuntime!
    private var identityFetcher: MockFlagIdentityFetcher!
    private var manager: FlagClientManager!

    override func setUp() {
        runtime = TestableExtensionRuntime()
        identityFetcher = MockFlagIdentityFetcher()
        let testRuntime = runtime!
        let syncQueue = ExposureQueueTestSupport.createDeterministicQueue { events in
            FlagEdgeHandler.dispatchExposureEvents(extensionRuntime: testRuntime, events: events)
        }
        manager = FlagClientManager(
            extensionRuntime: runtime,
            identityFetcher: identityFetcher,
            exposureQueue: syncQueue
        )
        FlagsMobileClientFactory.createOverride = nil
    }

    override func tearDown() {
        FlagsMobileClientFactory.createOverride = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func fullRequiredConfig() -> [String: Any] {
        [
            FlagConstants.Configuration.experienceCloudOrg: "test@AdobeOrg",
            FlagConstants.Configuration.flagsSandbox: "prod",
            FlagConstants.Configuration.flagsClientId: "client-123"
        ]
    }

    private func getFeatureEvent(featureName: String = "feature-key") -> Event {
        Event(
            name: FlagConstants.EventNames.getFeatureRequest,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            data: [
                FlagConstants.EventDataKeys.requestType: FlagConstants.EventDataValues.requestTypeGetFeature,
                FlagConstants.EventDataKeys.featureName: featureName
            ]
        )
    }

    private func isEnabledEvent(featureName: String = "feature-key") -> Event {
        Event(
            name: FlagConstants.EventNames.isFeatureEnabledRequest,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            data: [
                FlagConstants.EventDataKeys.requestType: FlagConstants.EventDataValues.requestTypeIsEnabled,
                FlagConstants.EventDataKeys.featureName: featureName
            ]
        )
    }

    private func responseEvents() -> [Event] {
        runtime.dispatchedEvents.filter { $0.source == FlagConstants.EventSource.responseContent }
    }

    private func edgeEvents() -> [Event] {
        runtime.dispatchedEvents.filter { $0.type == EventType.edge }
    }

    private func propositionDisplayEdgeEvents() -> [Event] {
        edgeEvents().filter { ExposureTestAssertions.isPropositionDisplayEdgeEvent($0) }
    }

    private func flushQueuedExposure() {
        manager.handleAppStateChange(.background)
    }

    private func featureResultWithAnalytics(
        featureGroupId: Int,
        featureGroupKey: String,
        featureId: Int,
        featureKey: String,
        variantId: String
    ) -> FlagsSDKFeatureResult {
        ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: featureGroupId,
            featureGroupKey: featureGroupKey,
            featureId: featureId,
            featureKey: featureKey,
            variantId: variantId
        )
    }

    // MARK: - Resolver contract

    // T-C1: Successful init resolves the pending shared state with `ready`.
    func testStartAsyncInitialization_success_resolvesReady() {
        FlagsMobileClientFactory.createOverride = { _ in MockFlagsMobileClient() }
        let exp = expectation(description: "resolve")
        var resolved: [String: Any]?
        manager.startAsyncInitialization(configData: fullRequiredConfig()) { data in
            resolved = data
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(resolved?[FlagConstants.SharedState.initializationStatus] as? String, FlagConstants.SharedState.statusReady)
        XCTAssertTrue(manager.isClientReady())
        XCTAssertEqual(1, identityFetcher.warmUpCallCount)
    }

    // T-C2: `FlagInitError` during create resolves the pending shared state with `failed`.
    func testStartAsyncInitialization_flagInitError_resolvesFailed() {
        FlagsMobileClientFactory.createOverride = { _ in
            throw FlagInitError.initializationFailed(message: "Test init failure", underlying: nil)
        }
        let exp = expectation(description: "resolve")
        var resolved: [String: Any]?
        manager.startAsyncInitialization(configData: fullRequiredConfig()) { data in
            resolved = data
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(resolved?[FlagConstants.SharedState.initializationStatus] as? String, FlagConstants.SharedState.statusFailed)
        XCTAssertFalse(manager.isClientReady())
    }

    // T-C3: `buildConfiguration` returns nil → synchronous `failed` resolve, no `initQueue` submit.
    func testStartAsyncInitialization_buildConfigNil_resolvesFailedSync() {
        var createCalled = false
        FlagsMobileClientFactory.createOverride = { _ in
            createCalled = true
            return MockFlagsMobileClient()
        }
        var resolved: [String: Any]?
        // Empty config data → buildConfiguration returns nil (missing required keys).
        manager.startAsyncInitialization(configData: [:]) { data in
            resolved = data
        }

        // Resolution happens synchronously before any async work.
        XCTAssertEqual(resolved?[FlagConstants.SharedState.initializationStatus] as? String, FlagConstants.SharedState.statusFailed)
        XCTAssertFalse(createCalled)
        XCTAssertFalse(manager.isInitializationInProgress())
        XCTAssertFalse(manager.isClientReady())
    }

    // T-C4: A second `startAsyncInitialization` while one is in progress does not resolve twice or re-init.
    func testStartAsyncInitialization_secondCallWhileInProgress_noDuplicate() {
        let gate = DispatchSemaphore(value: 0)
        let createCount = AtomicCounter()
        FlagsMobileClientFactory.createOverride = { _ in
            createCount.increment()
            gate.wait()
            return MockFlagsMobileClient()
        }
        let resolveExp = expectation(description: "resolve once")
        resolveExp.expectedFulfillmentCount = 1
        resolveExp.assertForOverFulfill = true
        let resolveCount = AtomicCounter()
        let resolver: SharedStateResolver = { _ in
            resolveCount.increment()
            resolveExp.fulfill()
        }

        // First call: sets initializationInProgress synchronously, then blocks in createOverride on initQueue.
        manager.startAsyncInitialization(configData: fullRequiredConfig(), resolver: resolver)
        XCTAssertTrue(manager.isInitializationInProgress())

        // Second call: must early-return (no second init, no second resolve).
        manager.startAsyncInitialization(configData: fullRequiredConfig(), resolver: resolver)

        gate.signal()
        wait(for: [resolveExp], timeout: 2.0)

        XCTAssertEqual(resolveCount.value, 1)
        XCTAssertEqual(createCount.value, 1)
    }

    // MARK: - Defensive processRequestEvent paths

    // T-6a: GET_FEATURE with no client set → one error response, no Edge event.
    func testProcessRequestEvent_getFeature_noClient_errors() {
        manager.processRequestEvent(getFeatureEvent())

        let responses = responseEvents()
        XCTAssertEqual(responses.count, 1)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
        XCTAssertTrue(edgeEvents().isEmpty)
    }

    // T-6b: IS_ENABLED with no client set → one error response, no Edge event.
    func testProcessRequestEvent_isEnabled_noClient_errors() {
        manager.processRequestEvent(isEnabledEvent())

        let responses = responseEvents()
        XCTAssertEqual(responses.count, 1)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
        XCTAssertTrue(edgeEvents().isEmpty)
    }

    // T-6c: client present but not initialized (its SDK call throws) → error response, no Edge event.
    func testProcessRequestEvent_clientNotInitialized_errors() {
        let mock = MockFlagsMobileClient()
        mock.getFeatureError = FlagClientError.operationFailed(message: "client not initialized", underlying: nil)
        manager.setFeatureClient(mock)
        manager.setFeatureClientInitialized(false)

        manager.processRequestEvent(getFeatureEvent())

        let responses = responseEvents()
        XCTAssertEqual(responses.count, 1)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
        XCTAssertTrue(edgeEvents().isEmpty)
    }

    func testProcessRequestEvent_getFeature_missingClientId_errorsWithoutEdgeDispatch() {
        let mock = MockFlagsMobileClient()
        mock.mobileClientId = ""
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent())

        let responses = responseEvents()
        XCTAssertEqual(1, responses.count)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
        XCTAssertTrue(edgeEvents().isEmpty)
        XCTAssertNil(mock.lastGetFeatureRequest)
    }

    func testProcessRequestEvent_isFeatureEnabled_missingClientId_errorsWithoutEdgeDispatch() {
        let mock = MockFlagsMobileClient()
        mock.mobileClientId = "   "
        initializeManager(with: mock)

        manager.processRequestEvent(isEnabledEvent())

        let responses = responseEvents()
        XCTAssertEqual(1, responses.count)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
        XCTAssertTrue(edgeEvents().isEmpty)
        XCTAssertNil(mock.lastGetFeatureRequest)
    }

    // MARK: - Identity map pass-through

    func testProcessRequestEvent_getFeature_passesIdentityMapToEngine() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-key",
            featureGroupKey: nil,
            value: nil,
            meta: nil,
            analyticsParam: nil
        )
        manager.setFeatureClient(mock)
        manager.setFeatureClientInitialized(true)

        identityFetcher.identityMap = [
            "ECID": [[
                IdentityMapMarshaller.keyId: "ecid-123",
                IdentityMapMarshaller.keyPrimary: true
            ]]
        ]

        manager.processRequestEvent(getFeatureEvent())

        let ecidEntries = mock.lastGetFeatureRequest?.identityMap["ECID"]
        XCTAssertEqual("ecid-123", ecidEntries?.first?[IdentityMapMarshaller.keyId] as? String)
        XCTAssertEqual(true, ecidEntries?.first?[IdentityMapMarshaller.keyPrimary] as? Bool)
    }

    // MARK: - Evaluation path

    private func initializeManager(with mock: MockFlagsMobileClient) {
        manager.setFeatureClient(mock)
        manager.setFeatureClientInitialized(true)
    }

    private func featureMap(from response: Event?) -> [String: Any]? {
        response?.data?[FlagConstants.EventDataKeys.feature] as? [String: Any]
    }

    func testProcessRequestEvent_isFeatureEnabled_usesGetFeature_notIsFeatureEnabled() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "dark-mode",
            featureGroupKey: nil,
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(featureGroupId: 23261, featureId: 1, featureKey: "dark-mode", variantId: "10283012")
        )
        initializeManager(with: mock)

        manager.processRequestEvent(isEnabledEvent(featureName: "dark-mode"))

        XCTAssertEqual(1, mock.lastGetFeatureRequest != nil ? 1 : 0)
        XCTAssertEqual(0, mock.isFeatureEnabledCallCount)
        XCTAssertNil(mock.lastIsFeatureEnabledRequest)

        let response = responseEvents().first
        XCTAssertEqual(true, response?.data?[FlagConstants.EventDataKeys.isEnabled] as? Bool)
        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)

        flushQueuedExposure()
        XCTAssertEqual(1, propositionDisplayEdgeEvents().count)
    }

    func testProcessRequestEvent_isFeatureEnabled_passesIdentityMapFromFetcher() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "dark-mode",
            featureGroupKey: nil,
            value: nil,
            meta: nil,
            analyticsParam: nil
        )
        initializeManager(with: mock)

        identityFetcher.identityMap = [
            "ECID": [[
                IdentityMapMarshaller.keyId: "ecid-456",
                IdentityMapMarshaller.keyPrimary: true
            ]]
        ]

        manager.processRequestEvent(isEnabledEvent(featureName: "dark-mode"))

        let ecidEntries = mock.lastGetFeatureRequest?.identityMap["ECID"]
        XCTAssertEqual("ecid-456", ecidEntries?.first?[IdentityMapMarshaller.keyId] as? String)
        XCTAssertEqual(0, mock.isFeatureEnabledCallCount)
    }

    func testProcessRequestEvent_isFeatureEnabled_nullIdentityMap_stillEvaluates() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = nil
        initializeManager(with: mock)
        identityFetcher.identityMap = nil

        manager.processRequestEvent(isEnabledEvent(featureName: "dark-mode"))

        XCTAssertTrue(mock.lastGetFeatureRequest?.identityMap.isEmpty ?? false)
        XCTAssertEqual(0, mock.isFeatureEnabledCallCount)

        let response = responseEvents().first
        XCTAssertEqual(false, response?.data?[FlagConstants.EventDataKeys.isEnabled] as? Bool)
        XCTAssertEqual(1, responseEvents().count)
        XCTAssertTrue(edgeEvents().isEmpty)
    }

    func testProcessRequestEvent_isFeatureEnabled_controlCohort_returnsFalse() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: -1,
            key: nil,
            featureGroupKey: "||features||",
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: "0")
        )
        initializeManager(with: mock)

        manager.processRequestEvent(isEnabledEvent(featureName: "checkout-flag"))

        let response = responseEvents().first
        XCTAssertEqual(false, response?.data?[FlagConstants.EventDataKeys.isEnabled] as? Bool)
        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)

        flushQueuedExposure()
        XCTAssertEqual(1, propositionDisplayEdgeEvents().count)
    }

    func testProcessRequestEvent_getFeature_metaPassThrough_preservesExactStringInFlagsResponse() {
        let mock = MockFlagsMobileClient()
        let metaJson = "{\"allowedLocales\":[\"en_US\",\"fr_FR\"],\"variant\":\"control\"}"
        mock.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-a",
            featureGroupKey: "fg-group",
            value: nil,
            meta: metaJson,
            analyticsParam: nil
        )
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "feature-a"))

        XCTAssertEqual(metaJson, featureMap(from: responseEvents().first)?[FlagConstants.EventDataKeys.meta] as? String)
    }

    func testProcessRequestEvent_getFeature_nullMeta_omitsMetaFromEvent() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-a",
            featureGroupKey: "fg-group",
            value: nil,
            meta: nil,
            analyticsParam: nil
        )
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "feature-a"))

        let featureMap = featureMap(from: responseEvents().first)
        XCTAssertNotNil(featureMap)
        XCTAssertNil(featureMap?[FlagConstants.EventDataKeys.meta])
        XCTAssertTrue(featureMap?.keys.contains(FlagConstants.EventDataKeys.key) ?? false)
    }

    func testProcessRequestEvent_getFeature_controlCohort_includesNullKeyInFeatureMap() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: -1,
            key: nil,
            featureGroupKey: "||features||",
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: "0")
        )
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "checkout-flag"))

        let featureMap = featureMap(from: responseEvents().first)
        XCTAssertTrue(featureMap?.keys.contains(FlagConstants.EventDataKeys.key) ?? false)
        XCTAssertTrue(featureMap?[FlagConstants.EventDataKeys.key] is NSNull)
        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)

        flushQueuedExposure()
        XCTAssertEqual(1, propositionDisplayEdgeEvents().count)
    }

    // MARK: - Exposure queue

    func testProcessRequestEvent_getFeature_eligibleFeature_doesNotDispatchEdgeBeforeFlush() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = featureResultWithAnalytics(
            featureGroupId: 23261,
            featureGroupKey: "fg-group",
            featureId: 1,
            featureKey: "feature-a",
            variantId: "10283012"
        )
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "feature-a"))

        XCTAssertEqual(1, responseEvents().count)
        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)
    }

    func testProcessRequestEvent_getFeature_nullVariantId_doesNotDispatchEdgeEvent() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: 173226,
            key: "checkout-flag",
            featureGroupKey: "||features||",
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: nil)
        )
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "checkout-flag"))
        flushQueuedExposure()

        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)
    }

    func testProcessRequestEvent_repeatedEvaluations_backgroundFlushAggregatesDisplayCount() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )
        initializeManager(with: mock)

        for _ in 0..<10 {
            manager.processRequestEvent(getFeatureEvent(featureName: "checkout-flag"))
        }

        flushQueuedExposure()

        XCTAssertEqual(1, propositionDisplayEdgeEvents().count)
        let decisioning = propositionDisplayEdgeEvents().first?.data?[FlagConstants.Edge.xdm] as? [String: Any]
        let experience = decisioning?[FlagConstants.Edge.experience] as? [String: Any]
        let decisioningPayload = experience?[FlagConstants.Edge.decisioning] as? [String: Any]
        let propositionEventType = decisioningPayload?[FlagConstants.Edge.propositionEventType] as? [String: Any]
        XCTAssertEqual(10, propositionEventType?[FlagConstants.Edge.display] as? Int)
    }

    func testAppStateChange_background_flushesQueuedExposure() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = featureResultWithAnalytics(
            featureGroupId: 23261,
            featureGroupKey: "fg-group",
            featureId: 1,
            featureKey: "feature-a",
            variantId: "10283012"
        )
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "feature-a"))
        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)

        manager.handleAppStateChange(.background)
        XCTAssertEqual(1, propositionDisplayEdgeEvents().count)
    }
}

/// Minimal thread-safe counter for asserting cross-thread invocation counts deterministically.
private final class AtomicCounter {
    private let queue = DispatchQueue(label: "com.adobe.flag.test.atomicCounter")
    private var count = 0

    func increment() {
        queue.sync { count += 1 }
    }

    var value: Int {
        queue.sync { count }
    }
}
