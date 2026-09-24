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

class FeatureResultMapperTests: XCTestCase {
    // MARK: - isEnabledFeatureResult

    func testIsEnabledFeatureResult_enabledKey_returnsTrue() {
        let feature = FlagsSDKFeatureResult(
            id: 1,
            key: "dark-mode",
            featureGroupKey: nil,
            value: nil,
            meta: nil,
            analyticsParam: nil
        )

        XCTAssertTrue(FeatureResultMapper.isEnabledFeatureResult(feature))
    }

    func testIsEnabledFeatureResult_nullFeature_returnsFalse() {
        XCTAssertFalse(FeatureResultMapper.isEnabledFeatureResult(nil))
    }

    func testIsEnabledFeatureResult_nullKey_returnsFalse() {
        let feature = FlagsSDKFeatureResult(
            id: -1,
            key: nil,
            featureGroupKey: "||features||",
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(featureGroupId: -1, featureId: 173226, featureKey: "checkout-flag", variantId: "0")
        )

        XCTAssertFalse(FeatureResultMapper.isEnabledFeatureResult(feature))
    }

    func testIsEnabledFeatureResult_emptyKey_returnsFalse() {
        let feature = FlagsSDKFeatureResult(
            id: 1,
            key: "",
            featureGroupKey: nil,
            value: nil,
            meta: nil,
            analyticsParam: nil
        )

        XCTAssertFalse(FeatureResultMapper.isEnabledFeatureResult(feature))
    }

    // MARK: - featureResultToMap

    func testFeatureResultToMap_alwaysIncludesKey_evenWhenNull() {
        let feature = FlagsSDKFeatureResult(
            id: -1,
            key: nil,
            featureGroupKey: "fg-group",
            value: nil,
            meta: nil,
            analyticsParam: nil
        )

        let map = FeatureResultMapper.featureResultToMap(feature)

        XCTAssertEqual(-1, map[FlagConstants.EventDataKeys.id] as? Int)
        XCTAssertTrue(map.keys.contains(FlagConstants.EventDataKeys.key))
        XCTAssertTrue(map[FlagConstants.EventDataKeys.key] is NSNull)
    }

    func testFeatureResultToMap_metaPassThrough_preservesExactString() {
        let metaJson = "{\"allowedLocales\":[\"en_US\",\"fr_FR\"],\"variant\":\"control\"}"
        let feature = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-a",
            featureGroupKey: "fg-group",
            value: nil,
            meta: metaJson,
            analyticsParam: nil
        )

        let map = FeatureResultMapper.featureResultToMap(feature)

        XCTAssertEqual(metaJson, map[FlagConstants.EventDataKeys.meta] as? String)
    }

    func testFeatureResultToMap_nullMeta_omitsMeta() {
        let feature = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-a",
            featureGroupKey: "fg-group",
            value: nil,
            meta: nil,
            analyticsParam: nil
        )

        let map = FeatureResultMapper.featureResultToMap(feature)

        XCTAssertNil(map[FlagConstants.EventDataKeys.meta])
    }

    func testFeatureResultToMap_whitespaceOnlyMeta_omitsMeta() {
        let feature = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-a",
            featureGroupKey: "fg-group",
            value: nil,
            meta: "   \n\t  ",
            analyticsParam: nil
        )

        let map = FeatureResultMapper.featureResultToMap(feature)

        XCTAssertNil(map[FlagConstants.EventDataKeys.meta])
    }

    func testFeatureResultToMap_metaRoundTripThroughResponseMapper_unchanged() throws {
        let metaJson = "{\"tags\":[\"a\",\"b\"],\"variant\":\"control\"}"
        let feature = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-a",
            featureGroupKey: "fg-group",
            value: nil,
            meta: metaJson,
            analyticsParam: nil
        )

        let map = FeatureResultMapper.featureResultToMap(feature)
        let result = try FlagResponseMapper.toFeatureEvaluationResult(map)

        XCTAssertEqual(metaJson, result?.meta)
    }

    func testFeatureResultToMap_includesAnalyticsWhenPresent() {
        let feature = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-a",
            featureGroupKey: "fg-group",
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(featureGroupId: 23261, featureId: 1, featureKey: "feature-a", variantId: "10283012")
        )

        let map = FeatureResultMapper.featureResultToMap(feature)
        let analytics = map[FlagConstants.EventDataKeys.analyticsParam] as? [String: Any]

        XCTAssertEqual(23261, analytics?[FlagConstants.EventDataKeys.featureGroupId] as? Int)
        XCTAssertEqual(1, analytics?[FlagConstants.EventDataKeys.featureId] as? Int)
        XCTAssertEqual("10283012", analytics?[FlagConstants.EventDataKeys.variantId] as? String)
    }
}
