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

final class FilterServiceCriteriaCacheTests: XCTestCase {

    private let types = ["country": "STRING"]

    func testCacheInvalidatesWhenCriteriaVersionChanges() {
        let fs = FilterService(fieldDataTypeCache: types)
        let usUser = UserAttributes.from(context: ["country": ["US"]])
        let ukUser = UserAttributes.from(context: ["country": ["UK"]])
        let logicalId = "feature:1:42:flag-a"
        let criteriaUs = #"{"criteria":{"attr":"country","operator":"EQ","val":"US"}}"#
        XCTAssertTrue(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: logicalId, criteriaJson: criteriaUs, criteriaVersion: "hash-us"))
        XCTAssertFalse(fs.evaluateCriteriaCached(userAttributes: ukUser, logicalId: logicalId, criteriaJson: criteriaUs, criteriaVersion: "hash-us"))

        let criteriaUk = #"{"criteria":{"attr":"country","operator":"EQ","val":"UK"}}"#
        XCTAssertTrue(fs.evaluateCriteriaCached(userAttributes: ukUser, logicalId: logicalId, criteriaJson: criteriaUk, criteriaVersion: "hash-uk"))
        XCTAssertFalse(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: logicalId, criteriaJson: criteriaUk, criteriaVersion: "hash-uk"))
    }

    func testRepeatedEvaluationSameLogicalIdUsesStableResult() {
        let fs = FilterService(fieldDataTypeCache: types)
        let usUser = UserAttributes.from(context: ["country": ["US"]])
        let logicalId = "featureGroup:9"
        let criteria = #"{"criteria":{"attr":"country","operator":"EQ","val":"US"}}"#
        XCTAssertTrue(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: logicalId, criteriaJson: criteria, criteriaVersion: "v1"))
        XCTAssertTrue(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: logicalId, criteriaJson: criteria, criteriaVersion: "v1"))
    }

    func testNullOrBlankLogicalIdSkipsCacheStillEvaluatesStrictly() {
        let fs = FilterService(fieldDataTypeCache: types)
        let usUser = UserAttributes.from(context: ["country": ["US"]])
        let ukUser = UserAttributes.from(context: ["country": ["UK"]])
        let criteriaUs = #"{"criteria":{"attr":"country","operator":"EQ","val":"US"}}"#
        let criteriaUk = #"{"criteria":{"attr":"country","operator":"EQ","val":"UK"}}"#

        XCTAssertTrue(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: nil, criteriaJson: criteriaUs, criteriaVersion: "a"))
        XCTAssertFalse(fs.evaluateCriteriaCached(userAttributes: ukUser, logicalId: nil, criteriaJson: criteriaUs, criteriaVersion: "a"))
        XCTAssertTrue(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: "  \t\n", criteriaJson: criteriaUs, criteriaVersion: "b"))
        XCTAssertFalse(fs.evaluateCriteriaCached(userAttributes: ukUser, logicalId: "", criteriaJson: criteriaUs, criteriaVersion: "c"))

        XCTAssertTrue(fs.matches(criteriaJson: criteriaUs, userAttributes: usUser))
        XCTAssertTrue(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: nil, criteriaJson: criteriaUs, criteriaVersion: "x"))
        XCTAssertFalse(fs.evaluateCriteriaCached(userAttributes: usUser, logicalId: nil, criteriaJson: criteriaUk, criteriaVersion: "y"))
    }
}
