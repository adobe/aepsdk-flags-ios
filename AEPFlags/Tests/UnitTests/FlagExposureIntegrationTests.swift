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

/// End-to-end tests for evaluation → queue → flush → Edge dispatch through `FlagClientManager`.
class FlagExposureIntegrationTests: XCTestCase {
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
    }

    override func tearDown() {
        manager.closeClient()
        super.tearDown()
    }

    private func initializeManager(with mock: MockFlagsMobileClient) {
        manager.setFeatureClient(mock)
        manager.setFeatureClientInitialized(true)
    }

    private func getFeatureEvent(featureName: String) -> Event {
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

    private func isEnabledEvent(featureName: String) -> Event {
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

    private func propositionDisplayEdgeEvents() -> [Event] {
        runtime.dispatchedEvents.filter { ExposureTestAssertions.isPropositionDisplayEdgeEvent($0) }
    }

    private func flushQueuedExposure() {
        manager.handleAppStateChange(.background)
    }

    private func standaloneFeature(featureId: Int, featureKey: String, variantId: String) -> FlagsSDKFeatureResult {
        ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: featureId,
            featureKey: featureKey,
            variantId: variantId
        )
    }

    private func featureGroupFeature(
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

    func testRepeatedEvaluations_sameCorrelationId_aggregateDisplayCountOnFlush() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = standaloneFeature(featureId: 173226, featureKey: "checkout-flag", variantId: "10283012")
        initializeManager(with: mock)

        for _ in 0..<5 {
            manager.processRequestEvent(getFeatureEvent(featureName: "checkout-flag"))
        }

        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)

        flushQueuedExposure()

        XCTAssertEqual(6, runtime.dispatchedEvents.count)
        guard let edgeEvent = ExposureTestAssertions.findEdgeEvent(runtime.dispatchedEvents) else {
            return XCTFail("Expected edge event")
        }
        XCTAssertEqual(5, ExposureTestAssertions.extractDisplayCount(edgeEvent))
        XCTAssertNotNil(ExposureTestAssertions.extractTimestamp(edgeEvent))
    }

    func testIsFeatureEnabled_controlCohort_queuesExposureUntilFlush() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = FlagsSDKFeatureResult(
            id: -1,
            key: nil,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: "0")
        )
        initializeManager(with: mock)

        manager.processRequestEvent(isEnabledEvent(featureName: "checkout-flag"))

        XCTAssertEqual(1, responseEvents().count)
        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)

        flushQueuedExposure()

        XCTAssertEqual(2, runtime.dispatchedEvents.count)
        guard let edgeEvent = ExposureTestAssertions.findEdgeEvent(runtime.dispatchedEvents) else {
            return XCTFail("Expected edge event")
        }
        XCTAssertEqual("F-173226-0", ExposureTestAssertions.extractCorrelationId(edgeEvent))
    }

    func testNullVariantId_neverQueuesExposureEvenAfterFlush() {
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

        XCTAssertEqual(1, runtime.dispatchedEvents.count)
        XCTAssertTrue(propositionDisplayEdgeEvents().isEmpty)
    }

    func testTwentyUniqueFeatures_autoFlushesTwentyEdgeEventsWithoutManualFlush() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = standaloneFeature(featureId: 1, featureKey: "feature-1", variantId: "10283012")
        initializeManager(with: mock)

        for index in 1...FlagConstants.ExposureQueue.batchSize {
            mock.featureResult = standaloneFeature(featureId: index, featureKey: "feature-\(index)", variantId: "10283012")
            manager.processRequestEvent(getFeatureEvent(featureName: "feature-\(index)"))
        }

        XCTAssertEqual(
            FlagConstants.ExposureQueue.batchSize,
            ExposureTestAssertions.countEdgeEvents(runtime.dispatchedEvents)
        )
    }

    func testFeatureGroup_buildsExpectedEdgePayloadOnBackgroundFlush() {
        let mock = MockFlagsMobileClient()
        mock.featureResult = featureGroupFeature(
            featureGroupId: 456789,
            featureGroupKey: "fg-group-v1",
            featureId: 1,
            featureKey: "feature-a",
            variantId: "10283013"
        )
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "feature-a"))
        flushQueuedExposure()

        XCTAssertEqual(2, runtime.dispatchedEvents.count)
        guard let edgeEvent = ExposureTestAssertions.findEdgeEvent(runtime.dispatchedEvents) else {
            return XCTFail("Expected edge event")
        }
        XCTAssertEqual("FG-456789-10283013", ExposureTestAssertions.extractCorrelationId(edgeEvent))
        XCTAssertTrue(ExposureTestAssertions.hasFeatureGroupItems(edgeEvent))
    }

    func testFeatureGroupDistinctFeatures_sameVariant_flushSeparatelyWithGroupCorrelationId() {
        let mock = MockFlagsMobileClient()
        let featureA = featureGroupFeature(
            featureGroupId: 456789,
            featureGroupKey: "fg-group-v1",
            featureId: 1,
            featureKey: "feature-a",
            variantId: "10283013"
        )
        let featureB = featureGroupFeature(
            featureGroupId: 456789,
            featureGroupKey: "fg-group-v1",
            featureId: 2,
            featureKey: "feature-b",
            variantId: "10283013"
        )

        mock.featureResult = featureA
        initializeManager(with: mock)

        manager.processRequestEvent(getFeatureEvent(featureName: "feature-a"))
        mock.featureResult = featureB
        manager.processRequestEvent(getFeatureEvent(featureName: "feature-b"))
        flushQueuedExposure()

        let edgeEvents = propositionDisplayEdgeEvents()
        XCTAssertEqual(2, edgeEvents.count)
        XCTAssertEqual("FG-456789-10283013", ExposureTestAssertions.extractCorrelationId(edgeEvents[0]))
        XCTAssertEqual("FG-456789-10283013", ExposureTestAssertions.extractCorrelationId(edgeEvents[1]))
        XCTAssertEqual(1, ExposureTestAssertions.extractDisplayCount(edgeEvents[0]))
        XCTAssertEqual(1, ExposureTestAssertions.extractDisplayCount(edgeEvents[1]))
    }
}
