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
import XCTest

class FlagResponseMapperTests: XCTestCase {
    func testToFeatureEvaluationResult_nullMap_returnsNil() throws {
        XCTAssertNil(try FlagResponseMapper.toFeatureEvaluationResult(nil))
    }

    func testToFeatureEvaluationResult_emptyMap_returnsNil() throws {
        XCTAssertNil(try FlagResponseMapper.toFeatureEvaluationResult([:]))
    }

    func testToFeatureEvaluationResult_validMinimal_parsesIdAndKey() throws {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 7,
            FlagConstants.EventDataKeys.key: "my-feature"
        ]

        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual(7, result.id)
        XCTAssertEqual("my-feature", result.key)
        XCTAssertNil(result.featureGroupKey)
        XCTAssertNil(result.meta)
        XCTAssertNil(result.analyticsParam)
    }

    func testToFeatureEvaluationResult_validFull_includesOptionalFieldsAndAnalytics() throws {
        let analytics: [String: Any] = [
            FlagConstants.EventDataKeys.featureGroupId: 100,
            FlagConstants.EventDataKeys.featureId: 200,
            FlagConstants.EventDataKeys.variantId: "v1"
        ]
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 1,
            FlagConstants.EventDataKeys.key: "k",
            FlagConstants.EventDataKeys.featureGroupKey: "rel-1",
            FlagConstants.EventDataKeys.meta: "{\"a\":1}",
            FlagConstants.EventDataKeys.analyticsParam: analytics
        ]

        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual(1, result.id)
        XCTAssertEqual("k", result.key)
        XCTAssertEqual("rel-1", result.featureGroupKey)
        XCTAssertEqual("{\"a\":1}", result.meta)
        XCTAssertEqual(100, result.analyticsParam?.featureGroupId)
        XCTAssertEqual(200, result.analyticsParam?.featureId)
        XCTAssertEqual("v1", result.analyticsParam?.variantId)
    }

    func testToFeatureEvaluationResult_missingId_throws() {
        let map: [String: Any] = [FlagConstants.EventDataKeys.key: "k"]
        XCTAssertThrowsError(try FlagResponseMapper.toFeatureEvaluationResult(map)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains(FlagConstants.EventDataKeys.id))
        }
    }

    func testToFeatureEvaluationResult_missingKey_throws() {
        let map: [String: Any] = [FlagConstants.EventDataKeys.id: 1]
        XCTAssertThrowsError(try FlagResponseMapper.toFeatureEvaluationResult(map)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains(FlagConstants.EventDataKeys.key))
        }
    }

    func testToFeatureEvaluationResult_emptyKey_throws() {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 1,
            FlagConstants.EventDataKeys.key: "   "
        ]
        XCTAssertThrowsError(try FlagResponseMapper.toFeatureEvaluationResult(map)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains(FlagConstants.EventDataKeys.key))
        }
    }

    func testToFeatureEvaluationResult_idCoercedFromString() throws {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: " 99 ",
            FlagConstants.EventDataKeys.key: "k"
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual(99, result.id)
    }

    func testToFeatureEvaluationResult_keyCoercedFromNumber() throws {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 1,
            FlagConstants.EventDataKeys.key: 55
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual("55", result.key)
    }

    func testToFeatureEvaluationResult_metaString_passThroughUnmodified() throws {
        let meta = "{\"tags\":[\"a\",\"b\"],\"flag\":\"ZmxhZ19mb3I=\"}"
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 1,
            FlagConstants.EventDataKeys.key: "k",
            FlagConstants.EventDataKeys.meta: meta
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual(meta, result.meta)
    }

    func testToFeatureEvaluationResult_idCoercedFromDouble() throws {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 42.9,
            FlagConstants.EventDataKeys.key: "k"
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual(42, result.id)
    }

    func testToFeatureEvaluationResult_idMalformedString_throws() {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: "not-a-number",
            FlagConstants.EventDataKeys.key: "k"
        ]
        XCTAssertThrowsError(try FlagResponseMapper.toFeatureEvaluationResult(map)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains("Invalid numeric"))
        }
    }

    func testToFeatureEvaluationResult_idWrongType_throws() {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: [1],
            FlagConstants.EventDataKeys.key: "k"
        ]
        XCTAssertThrowsError(try FlagResponseMapper.toFeatureEvaluationResult(map)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains("Invalid numeric"))
        }
    }

    func testToFeatureEvaluationResult_optionalFeatureGroupKeyCoercedFromNumber() throws {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 1,
            FlagConstants.EventDataKeys.key: "k",
            FlagConstants.EventDataKeys.featureGroupKey: 3
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual("3", result.featureGroupKey)
    }

    func testToFeatureEvaluationResult_metaMap_ignored() throws {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 1,
            FlagConstants.EventDataKeys.key: "k",
            FlagConstants.EventDataKeys.meta: ["a": 1]
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertNil(result.meta)
    }

    func testToFeatureEvaluationResult_optionalMetaCoercedFromBoolean() throws {
        let map: [String: Any] = [
            FlagConstants.EventDataKeys.id: 1,
            FlagConstants.EventDataKeys.key: "k",
            FlagConstants.EventDataKeys.meta: true
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toFeatureEvaluationResult(map))
        XCTAssertEqual("true", result.meta)
    }

    func testToAnalyticsParam_null_returnsNil() throws {
        XCTAssertNil(try FlagResponseMapper.toAnalyticsParam(nil))
    }

    func testToAnalyticsParam_notMap_returnsNil() throws {
        XCTAssertNil(try FlagResponseMapper.toAnalyticsParam("x"))
    }

    func testToAnalyticsParam_emptyMap_returnsNil() throws {
        XCTAssertNil(try FlagResponseMapper.toAnalyticsParam([:]))
    }

    func testToAnalyticsParam_valid_mapsFields() throws {
        let analytics: [String: Any] = [
            FlagConstants.EventDataKeys.featureGroupId: 10,
            FlagConstants.EventDataKeys.featureId: 20,
            FlagConstants.EventDataKeys.variantId: "v1"
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toAnalyticsParam(analytics))
        XCTAssertEqual(10, result.featureGroupId)
        XCTAssertEqual(20, result.featureId)
        XCTAssertEqual("v1", result.variantId)
    }

    func testToAnalyticsParam_missingFeatureGroupId_throws() {
        let analytics: [String: Any] = [FlagConstants.EventDataKeys.featureId: 20]
        XCTAssertThrowsError(try FlagResponseMapper.toAnalyticsParam(analytics)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains(FlagConstants.EventDataKeys.featureGroupId))
        }
    }

    func testToAnalyticsParam_missingFeatureId_throws() {
        let analytics: [String: Any] = [FlagConstants.EventDataKeys.featureGroupId: 10]
        XCTAssertThrowsError(try FlagResponseMapper.toAnalyticsParam(analytics)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains(FlagConstants.EventDataKeys.featureId))
        }
    }

    func testToAnalyticsParam_numericIdsCoercedFromString() throws {
        let analytics: [String: Any] = [
            FlagConstants.EventDataKeys.featureGroupId: " 11 ",
            FlagConstants.EventDataKeys.featureId: "22"
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toAnalyticsParam(analytics))
        XCTAssertEqual(11, result.featureGroupId)
        XCTAssertEqual(22, result.featureId)
        XCTAssertNil(result.variantId)
    }

    func testToAnalyticsParam_optionalStringsOmitted_nullInModel() throws {
        let analytics: [String: Any] = [
            FlagConstants.EventDataKeys.featureGroupId: 1,
            FlagConstants.EventDataKeys.featureId: 2
        ]
        let result = try XCTUnwrap(FlagResponseMapper.toAnalyticsParam(analytics))
        XCTAssertNil(result.variantId)
    }
}
