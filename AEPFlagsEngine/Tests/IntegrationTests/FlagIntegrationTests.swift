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

final class FlagIntegrationTests: XCTestCase {

    func testLocalEvaluationWithFilterService() {
        let fs = FilterService(fieldDataTypeCache: ["country": "STRING", "age": "INTEGER"])
        let criteria = #"{"criteria": {"and": [{"attr": "country", "operator": "EQ", "val": "US"},{"attr": "age", "operator": "GT", "val": 18}]}}"#
        let matching = UserAttributes().addAttribute("US", forKey: "country").addAttribute("25", forKey: "age")
        let nonMatching = UserAttributes().addAttribute("UK", forKey: "country").addAttribute("25", forKey: "age")
        XCTAssertTrue(fs.matches(criteriaJson: criteria, userAttributes: matching))
        XCTAssertFalse(fs.matches(criteriaJson: criteria, userAttributes: nonMatching))
    }

    func testPolicyEvaluatorDeterministic() {
        let userId = "test_user_123"
        let policyId = 100
        let r1 = PolicyEvaluator.getPolicyVariant(policyId: policyId, identifier: userId, controlPercentage: 50)
        let r2 = PolicyEvaluator.getPolicyVariant(policyId: policyId, identifier: userId, controlPercentage: 50)
        XCTAssertEqual(r1.variantId, r2.variantId)
        XCTAssertEqual(r1.controlGroup, r2.controlGroup)
    }

    func testPerformanceBenchmarkTenThousandEvaluations() {
        let fs = FilterService(fieldDataTypeCache: [
            "country": "STRING", "age": "INTEGER", "platform": "STRING", "appVersion": "VERSION"
        ])
        let criteria = #"{"criteria": {"and": [{"attr": "country", "operator": "IN", "val": ["US", "CA", "UK", "DE", "FR"]},{"attr": "age", "operator": "BW", "val": [18, 65]},{"attr": "platform", "operator": "EQ", "val": "Android"},{"attr": "appVersion", "operator": "VERSION_GT", "val": "1.0.0"}]}}"#
        let user = UserAttributes()
            .addAttribute("US", forKey: "country")
            .addAttribute("30", forKey: "age")
            .addAttribute("Android", forKey: "platform")
            .addAttribute("2.5.0", forKey: "appVersion")
        for _ in 0..<1000 { _ = fs.matches(criteriaJson: criteria, userAttributes: user) }
        let iterations = 10_000
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { _ = fs.matches(criteriaJson: criteria, userAttributes: user) }
        let elapsed = DispatchTime.now().uptimeNanoseconds - t0
        let micros = Double(elapsed) / 1000.0 / Double(iterations)
        let totalMs = Double(elapsed) / 1_000_000.0
        XCTAssertLessThan(micros, 500, "avg \(micros) µs per eval")
        XCTAssertLessThan(totalMs, 5000, "10k evals should finish in a few seconds on CI")
    }
}
