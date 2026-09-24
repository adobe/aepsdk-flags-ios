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

final class RuleProcessorStandaloneTests: XCTestCase {

    private var types: [String: String] {
        ["country": "STRING", "age": "INTEGER", "platform": "STRING", "premium": "BOOLEAN", "ipAddress": "IP_ADDR"]
    }

    func testBasicOperators() {
        let engine = RuleProcessor(fieldDataTypeCache: types)
        let eq = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        XCTAssertTrue(engine.evaluate(criteriaJson: eq, userAttributes: UserAttributes().addAttribute("US", forKey: "country")))
        XCTAssertFalse(engine.evaluate(criteriaJson: eq, userAttributes: UserAttributes().addAttribute("UK", forKey: "country")))

        let gt = #"{"criteria": {"attr": "age", "operator": "GT", "val": 18}}"#
        XCTAssertTrue(engine.evaluate(criteriaJson: gt, userAttributes: UserAttributes().addAttribute("25", forKey: "age")))
        XCTAssertFalse(engine.evaluate(criteriaJson: gt, userAttributes: UserAttributes().addAttribute("16", forKey: "age")))

        let `in` = #"{"criteria": {"attr": "platform", "operator": "IN", "val": ["iOS", "Android"]}}"#
        XCTAssertTrue(engine.evaluate(criteriaJson: `in`, userAttributes: UserAttributes().addAttribute("Android", forKey: "platform")))
        XCTAssertFalse(engine.evaluate(criteriaJson: `in`, userAttributes: UserAttributes().addAttribute("Web", forKey: "platform")))
    }

    func testComplexNestedRules() {
        let engine = RuleProcessor(fieldDataTypeCache: types)
        let criteria = #"{"criteria": {"and": [{"attr": "country", "operator": "EQ", "val": "US"},{"or": [{"attr": "age", "operator": "GT", "val": 21},{"attr": "premium", "operator": "EQ", "val": true}]}]}}"#

        let usAdult = UserAttributes().addAttribute("US", forKey: "country").addAttribute("30", forKey: "age").addAttribute("false", forKey: "premium")
        XCTAssertTrue(engine.evaluate(criteriaJson: criteria, userAttributes: usAdult))

        let usPremiumMinor = UserAttributes().addAttribute("US", forKey: "country").addAttribute("18", forKey: "age").addAttribute("true", forKey: "premium")
        XCTAssertTrue(engine.evaluate(criteriaJson: criteria, userAttributes: usPremiumMinor))

        let usNonQualified = UserAttributes().addAttribute("US", forKey: "country").addAttribute("18", forKey: "age").addAttribute("false", forKey: "premium")
        XCTAssertFalse(engine.evaluate(criteriaJson: criteria, userAttributes: usNonQualified))

        let ukAdult = UserAttributes().addAttribute("UK", forKey: "country").addAttribute("30", forKey: "age").addAttribute("true", forKey: "premium")
        XCTAssertFalse(engine.evaluate(criteriaJson: criteria, userAttributes: ukAdult))
    }

    func testPolicyDeterminism() {
        let r1 = PolicyEvaluator.getPolicyVariant(policyId: 100, identifier: "test_user_123", controlPercentage: 50)
        let r2 = PolicyEvaluator.getPolicyVariant(policyId: 100, identifier: "test_user_123", controlPercentage: 50)
        XCTAssertEqual(r1.variantId, r2.variantId)
        XCTAssertEqual(r1.controlGroup, r2.controlGroup)
    }

    func testNotNegate() {
        let engine = RuleProcessor(fieldDataTypeCache: ["country": "STRING"])
        let criteria = #"{"criteria": {"not": [{"attr": "country", "operator": "EQ", "val": "US"}]}}"#
        XCTAssertFalse(engine.evaluate(criteriaJson: criteria, userAttributes: UserAttributes().addAttribute("US", forKey: "country")))
        XCTAssertTrue(engine.evaluate(criteriaJson: criteria, userAttributes: UserAttributes().addAttribute("UK", forKey: "country")))
    }

    func testNotWithAnd() {
        let engine = RuleProcessor(fieldDataTypeCache: ["country": "STRING", "banned": "BOOLEAN"])
        let criteria = #"{"criteria": {"and": [{"attr": "country", "operator": "EQ", "val": "US"},{"not": [{"attr": "banned", "operator": "EQ", "val": true}]}]}}"#

        XCTAssertTrue(engine.evaluate(criteriaJson: criteria, userAttributes: UserAttributes().addAttribute("US", forKey: "country").addAttribute("false", forKey: "banned")))
        XCTAssertFalse(engine.evaluate(criteriaJson: criteria, userAttributes: UserAttributes().addAttribute("US", forKey: "country").addAttribute("true", forKey: "banned")))
        XCTAssertFalse(engine.evaluate(criteriaJson: criteria, userAttributes: UserAttributes().addAttribute("UK", forKey: "country").addAttribute("false", forKey: "banned")))
    }

    func testCidrMatchingViaRuleProcessor() {
        let engine = RuleProcessor(fieldDataTypeCache: ["ipAddress": "IP_ADDR"])
        let criteria = #"{"criteria": {"attr": "ipAddress", "operator": "IPO", "val": "10.0.0.0/8"}}"#
        XCTAssertTrue(engine.evaluate(criteriaJson: criteria, userAttributes: UserAttributes().addAttribute("10.50.100.200", forKey: "ipAddress")))
        XCTAssertFalse(engine.evaluate(criteriaJson: criteria, userAttributes: UserAttributes().addAttribute("8.8.8.8", forKey: "ipAddress")))
    }

    func testPerformanceTenThousandEvaluations() {
        let engine = RuleProcessor(fieldDataTypeCache: [
            "country": "STRING", "age": "INTEGER", "platform": "STRING", "appVersion": "VERSION"
        ])
        let criteria = #"{"criteria": {"and": [{"attr": "country", "operator": "IN", "val": ["US", "CA", "UK", "DE", "FR"]},{"attr": "age", "operator": "BW", "val": [18, 65]},{"attr": "platform", "operator": "EQ", "val": "Android"},{"attr": "appVersion", "operator": "VERSION_GT", "val": "1.0.0"}]}}"#
        let user = UserAttributes().addAttribute("US", forKey: "country").addAttribute("30", forKey: "age").addAttribute("Android", forKey: "platform").addAttribute("2.5.0", forKey: "appVersion")
        for _ in 0..<1000 { _ = engine.evaluate(criteriaJson: criteria, userAttributes: user) }
        let iterations = 10_000
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { _ = engine.evaluate(criteriaJson: criteria, userAttributes: user) }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        XCTAssertLessThan(elapsedMs, 2000, "10K evaluations should complete quickly")
    }
}
