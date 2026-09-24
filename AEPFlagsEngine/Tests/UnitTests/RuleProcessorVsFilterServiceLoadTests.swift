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

/// Compares RuleProcessor and FilterService evaluation outcomes.
final class RuleProcessorVsFilterServiceLoadTests: XCTestCase {

    private let fieldTypes: [String: String] = ["country": "STRING", "tier": "STRING"]
    private let criteria = #"{"criteria":{"and":[{"attr":"country","operator":"EQ","val":"US"},{"attr":"tier","operator":"IN","val":["gold","platinum"]}]}}"#

    func testRuleProcessorMatchesFilterServiceOutcomes() {
        let ruleProcessor = RuleProcessor(fieldDataTypeCache: fieldTypes)
        let filterService = FilterService(fieldDataTypeCache: fieldTypes)
        let matching = UserAttributes.from(context: ["country": ["US"], "tier": ["gold"]])
        let nonMatching = UserAttributes.from(context: ["country": ["US"], "tier": ["bronze"]])

        XCTAssertEqual(ruleProcessor.evaluate(criteriaJson: criteria, userAttributes: matching),
                       filterService.matches(criteriaJson: criteria, userAttributes: matching))
        XCTAssertEqual(ruleProcessor.evaluate(criteriaJson: criteria, userAttributes: nonMatching),
                       filterService.matches(criteriaJson: criteria, userAttributes: nonMatching))
        XCTAssertEqual(ruleProcessor.evaluate(criteriaJson: criteria, userAttributes: matching),
                       filterService.evaluateCriteriaCached(userAttributes: matching,
                                                            logicalId: "load:logical",
                                                            criteriaJson: criteria,
                                                            criteriaVersion: "h1"))
    }

    func testWarmMicroBenchmarkDoesNotCrash() {
        let ruleProcessor = RuleProcessor(fieldDataTypeCache: fieldTypes)
        let filterService = FilterService(fieldDataTypeCache: fieldTypes)
        let user = UserAttributes.from(context: ["country": ["US"], "tier": ["platinum"]])
        var mismatches = 0
        for _ in 0..<500 {
            let a = ruleProcessor.evaluate(criteriaJson: criteria, userAttributes: user)
            let b = filterService.matches(criteriaJson: criteria, userAttributes: user)
            let c = filterService.evaluateCriteriaCached(userAttributes: user,
                                                         logicalId: "bench:id",
                                                         criteriaJson: criteria,
                                                         criteriaVersion: "bench-hash")
            if a != b || a != c { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0, "RuleProcessor, FilterService.matches, and cached path must agree")
    }
}
