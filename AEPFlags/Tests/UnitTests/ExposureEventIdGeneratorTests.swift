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
import FlagsEngine
import XCTest

class ExposureEventIdGeneratorTests: XCTestCase {
    func testGenerateAggregationKey_nullFeature_returnsNil() {
        XCTAssertNil(ExposureEventIdGenerator.generateAggregationKey(nil))
    }

    func testGenerateCorrelationId_nullFeature_returnsNil() {
        XCTAssertNil(ExposureEventIdGenerator.generateCorrelationId(nil))
    }

    func testGenerateAggregationKey_nullAnalytics_returnsNil() {
        let feature = FlagsSDKFeatureResult(
            id: 1, key: "feature-a", featureGroupKey: "fg-group", value: nil, meta: nil, analyticsParam: nil
        )
        XCTAssertNil(ExposureEventIdGenerator.generateAggregationKey(feature))
    }

    func testGenerateAggregationKey_nullVariantId_returnsNil() {
        let analytics = AnalyticsParam(featureGroupId: 23261, featureId: 1, featureKey: "feature-a", variantId: nil)
        let feature = FlagsSDKFeatureResult(
            id: 1, key: "feature-a", featureGroupKey: "fg-group", value: nil, meta: nil, analyticsParam: analytics
        )
        XCTAssertNil(ExposureEventIdGenerator.generateAggregationKey(feature))
    }

    func testGenerateAggregationKey_standaloneFeature_matchesCorrelationId() {
        let analytics = AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: "10283012")
        let feature = FlagsSDKFeatureResult(
            id: 173226,
            key: "checkout-flag",
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            value: nil,
            meta: nil,
            analyticsParam: analytics
        )

        XCTAssertEqual("F-173226-10283012", ExposureEventIdGenerator.generateAggregationKey(feature))
        XCTAssertEqual(
            ExposureEventIdGenerator.generateAggregationKey(feature),
            ExposureEventIdGenerator.generateCorrelationId(feature)
        )
    }

    func testGenerateAggregationKey_featureGroup_includesFeatureId() {
        let analytics = AnalyticsParam(featureGroupId: 23261, featureId: 1, featureKey: "feature-a", variantId: "10283012")
        let feature = FlagsSDKFeatureResult(
            id: 1, key: "feature-a", featureGroupKey: "fg-group", value: nil, meta: nil, analyticsParam: analytics
        )

        XCTAssertEqual("FG-23261-1-10283012", ExposureEventIdGenerator.generateAggregationKey(feature))
        XCTAssertEqual("FG-23261-10283012", ExposureEventIdGenerator.generateCorrelationId(feature))
    }

    func testGenerateAggregationKey_featureGroup_distinctFeaturesProduceDistinctKeys() {
        let analyticsA = AnalyticsParam(featureGroupId: 23261, featureId: 1, featureKey: "feature-a", variantId: "10283012")
        let featureA = FlagsSDKFeatureResult(
            id: 1, key: "feature-a", featureGroupKey: "fg-group", value: nil, meta: nil, analyticsParam: analyticsA
        )
        let analyticsB = AnalyticsParam(featureGroupId: 23261, featureId: 2, featureKey: "feature-b", variantId: "10283012")
        let featureB = FlagsSDKFeatureResult(
            id: 2, key: "feature-b", featureGroupKey: "fg-group", value: nil, meta: nil, analyticsParam: analyticsB
        )

        XCTAssertEqual("FG-23261-1-10283012", ExposureEventIdGenerator.generateAggregationKey(featureA))
        XCTAssertEqual("FG-23261-2-10283012", ExposureEventIdGenerator.generateAggregationKey(featureB))
        XCTAssertEqual(
            ExposureEventIdGenerator.generateCorrelationId(featureA),
            ExposureEventIdGenerator.generateCorrelationId(featureB)
        )
    }

    func testGenerateCorrelationId_controlCohortVariantZero_includesVariantInCorrelationId() {
        let analytics = AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: "0")
        let feature = FlagsSDKFeatureResult(
            id: -1,
            key: nil,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            value: nil,
            meta: nil,
            analyticsParam: analytics
        )

        XCTAssertEqual("F-173226-0", ExposureEventIdGenerator.generateCorrelationId(feature))
        XCTAssertEqual(
            ExposureEventIdGenerator.generateCorrelationId(feature),
            ExposureEventIdGenerator.generateAggregationKey(feature)
        )
    }
}
