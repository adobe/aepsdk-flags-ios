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

class FlagEdgeHandlerTests: XCTestCase {
    private var runtime: TestableExtensionRuntime!

    private let defaultEvaluatedAtMillis: Int64 = 1_700_000_000_000

    override func setUp() {
        runtime = TestableExtensionRuntime()
    }

    private func edgeEvents() -> [Event] {
        runtime.dispatchedEvents.filter { $0.type == EventType.edge }
    }

    private func requestPath(in eventData: [String: Any]?) -> String? {
        guard let request = eventData?[FlagConstants.Edge.Request.key] as? [String: Any] else {
            return nil
        }
        return request[FlagConstants.Edge.Request.path] as? String
    }

    private func extractXdm(_ event: Event) -> [String: Any]? {
        event.data?[FlagConstants.Edge.xdm] as? [String: Any]
    }

    private func extractDecisioning(_ event: Event) -> [String: Any]? {
        guard let xdm = extractXdm(event),
              let experience = xdm[FlagConstants.Edge.experience] as? [String: Any] else {
            return nil
        }
        return experience[FlagConstants.Edge.decisioning] as? [String: Any]
    }

    private func extractScopeDetails(_ event: Event) -> [String: Any]? {
        guard let decisioning = extractDecisioning(event),
              let propositions = decisioning[FlagConstants.Edge.propositions] as? [[String: Any]],
              let first = propositions.first else {
            return nil
        }
        return first[FlagConstants.Edge.scopeDetails] as? [String: Any]
    }

    private func dispatchExposure(_ feature: FlagsSDKFeatureResult?, displayCount: Int) {
        guard let feature,
              let aggregationKey = ExposureEventIdGenerator.generateAggregationKey(feature) else {
            return
        }

        let event = AggregatedExposureEvent(
            aggregationKey: aggregationKey,
            feature: feature,
            lastEvaluatedAtMillis: defaultEvaluatedAtMillis,
            displayCount: displayCount
        )
        try? FlagEdgeHandler.dispatchExposureEvent(extensionRuntime: runtime, event: event)
    }

    func testDispatchExposureEvent_includesCollectRequestPath() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )

        dispatchExposure(feature, displayCount: 1)

        let edgeEvent = edgeEvents().first
        XCTAssertEqual(FlagConstants.Edge.Request.collectPath, requestPath(in: edgeEvent?.data))
    }

    func testDispatchExposureEvent_dispatchesEdgeEvent() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )

        dispatchExposure(feature, displayCount: 1)

        let edgeEvent = edgeEvents().first
        XCTAssertEqual(1, edgeEvents().count)
        XCTAssertEqual(EventSource.requestContent, edgeEvent?.source)
        XCTAssertEqual(FlagConstants.EventNames.edgeFeatureExposureRequest, edgeEvent?.name)
    }

    func testDispatchExposureEvent_xdmContainsPropositionDisplayEventType() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )

        dispatchExposure(feature, displayCount: 1)

        guard let edgeEvent = edgeEvents().first else {
            return XCTFail("Expected edge event")
        }
        XCTAssertEqual(FlagConstants.Edge.eventTypePropositionDisplay, extractXdm(edgeEvent)?[FlagConstants.Edge.eventType] as? String)
    }

    func testDispatchExposureEvent_standaloneFeature_buildsFeatureScopeDetails() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )

        dispatchExposure(feature, displayCount: 1)

        guard let edgeEvent = edgeEvents().first else {
            return XCTFail("Expected edge event")
        }
        let scopeDetails = extractScopeDetails(edgeEvent)
        XCTAssertEqual(FlagConstants.Edge.decisionProviderFlags, scopeDetails?[FlagConstants.Edge.decisionProvider] as? String)
        XCTAssertEqual("F-173226-10283012", scopeDetails?[FlagConstants.Edge.correlationId] as? String)

        let activity = scopeDetails?[FlagConstants.Edge.activity] as? [String: Any]
        XCTAssertEqual("F-173226", activity?[FlagConstants.Edge.identityId] as? String)
        XCTAssertEqual("checkout-flag", activity?[FlagConstants.Edge.name] as? String)

        let experience = scopeDetails?[FlagConstants.Edge.scopeExperience] as? [String: Any]
        XCTAssertEqual("Variant-10283012", experience?[FlagConstants.Edge.identityId] as? String)

        let characteristics = scopeDetails?[FlagConstants.Edge.characteristics] as? [String: Any]
        XCTAssertEqual(FlagConstants.Edge.entityTypeFeature, characteristics?[FlagConstants.Edge.entityType] as? String)
    }

    func testDispatchExposureEvent_featureGroup_buildsFeatureGroupScopeDetailsWithItems() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: 456789,
            featureGroupKey: "checkout-experiment",
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283013"
        )

        dispatchExposure(feature, displayCount: 1)

        guard let edgeEvent = edgeEvents().first else {
            return XCTFail("Expected edge event")
        }
        let scopeDetails = extractScopeDetails(edgeEvent)
        XCTAssertEqual("FG-456789-10283013", scopeDetails?[FlagConstants.Edge.correlationId] as? String)

        let activity = scopeDetails?[FlagConstants.Edge.activity] as? [String: Any]
        XCTAssertEqual("FG-456789", activity?[FlagConstants.Edge.identityId] as? String)
        XCTAssertEqual("checkout-experiment", activity?[FlagConstants.Edge.name] as? String)

        let characteristics = scopeDetails?[FlagConstants.Edge.characteristics] as? [String: Any]
        XCTAssertEqual(FlagConstants.Edge.entityTypeFeatureGroup, characteristics?[FlagConstants.Edge.entityType] as? String)

        let decisioning = extractDecisioning(edgeEvent)
        let propositions = decisioning?[FlagConstants.Edge.propositions] as? [[String: Any]]
        let items = propositions?.first?[FlagConstants.Edge.items] as? [[String: Any]]
        XCTAssertEqual("173226", items?.first?[FlagConstants.Edge.identityId] as? String)
        XCTAssertEqual("checkout-flag", items?.first?[FlagConstants.Edge.name] as? String)
    }

    func testDispatchExposureEvent_includesDisplayCount() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )

        dispatchExposure(feature, displayCount: 7)

        guard let edgeEvent = edgeEvents().first else {
            return XCTFail("Expected edge event")
        }
        let decisioning = extractDecisioning(edgeEvent)
        let propositionEventType = decisioning?[FlagConstants.Edge.propositionEventType] as? [String: Any]
        XCTAssertEqual(7, propositionEventType?[FlagConstants.Edge.display] as? Int)
    }

    func testDispatchExposureEvent_doesNotIncludeIdentityMap() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )

        dispatchExposure(feature, displayCount: 1)

        guard let edgeEvent = edgeEvents().first else {
            return XCTFail("Expected edge event")
        }
        let xdm = extractXdm(edgeEvent)
        XCTAssertNil(xdm?[FlagConstants.Edge.identityMap])
    }

    func testDispatchExposureEvent_nilVariantId_doesNotDispatch() {
        let analytics = AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: nil)
        let feature = FlagsSDKFeatureResult(
            id: 173226,
            key: "checkout-flag",
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            value: nil,
            meta: nil,
            analyticsParam: analytics
        )

        dispatchExposure(feature, displayCount: 1)

        XCTAssertTrue(edgeEvents().isEmpty)
    }

    func testDispatchExposureEvent_includesLastEvaluationTimestamp() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )
        let event = AggregatedExposureEvent(
            aggregationKey: "F-173226-10283012",
            feature: feature,
            lastEvaluatedAtMillis: 1_700_000_000_000,
            displayCount: 1
        )

        XCTAssertNoThrow(try FlagEdgeHandler.dispatchExposureEvent(extensionRuntime: runtime, event: event))

        guard let edgeEvent = edgeEvents().first else {
            return XCTFail("Expected edge event")
        }
        XCTAssertEqual("2023-11-14T22:13:20Z", ExposureTestAssertions.extractTimestamp(edgeEvent))
    }

    func testDispatchExposureEvent_includesLastEvaluationTimestamp_withNonZeroMillis() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )
        let event = AggregatedExposureEvent(
            aggregationKey: "F-173226-10283012",
            feature: feature,
            lastEvaluatedAtMillis: 1_700_000_000_123,
            displayCount: 1
        )

        XCTAssertNoThrow(try FlagEdgeHandler.dispatchExposureEvent(extensionRuntime: runtime, event: event))

        guard let edgeEvent = edgeEvents().first else {
            return XCTFail("Expected edge event")
        }
        XCTAssertEqual("2023-11-14T22:13:20.123Z", ExposureTestAssertions.extractTimestamp(edgeEvent))
    }

    func testDispatchExposureEvent_zeroDisplayCount_doesNotDispatch() {
        let feature = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 173226,
            featureKey: "checkout-flag",
            variantId: "10283012"
        )
        let event = AggregatedExposureEvent(
            aggregationKey: "F-173226-10283012",
            feature: feature,
            lastEvaluatedAtMillis: defaultEvaluatedAtMillis,
            displayCount: 0
        )

        XCTAssertNoThrow(try FlagEdgeHandler.dispatchExposureEvent(extensionRuntime: runtime, event: event))
        XCTAssertTrue(edgeEvents().isEmpty)
    }

    func testDispatchExposureEvents_continuesAfterSingleEventFailure() {
        let featureOne = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 1,
            featureKey: "feature-one",
            variantId: "10283012"
        )
        let featureTwo = ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: 2,
            featureKey: "feature-two",
            variantId: "10283013"
        )
        let eventOne = AggregatedExposureEvent(
            aggregationKey: "F-1-10283012",
            feature: featureOne,
            lastEvaluatedAtMillis: defaultEvaluatedAtMillis,
            displayCount: 1
        )
        let eventTwo = AggregatedExposureEvent(
            aggregationKey: "F-2-10283013",
            feature: featureTwo,
            lastEvaluatedAtMillis: defaultEvaluatedAtMillis + 1,
            displayCount: 3
        )

        runtime.failEdgeDispatchOnAttempts = [1]
        FlagEdgeHandler.dispatchExposureEvents(extensionRuntime: runtime, events: [eventOne, eventTwo])

        XCTAssertEqual(2, runtime.edgeDispatchAttemptCount)
        XCTAssertEqual(1, edgeEvents().count)

        let survivor = edgeEvents().first
        XCTAssertEqual(3, ExposureTestAssertions.extractDisplayCount(survivor!))
        XCTAssertEqual("F-2-10283013", ExposureTestAssertions.extractCorrelationId(survivor!))
    }
}
