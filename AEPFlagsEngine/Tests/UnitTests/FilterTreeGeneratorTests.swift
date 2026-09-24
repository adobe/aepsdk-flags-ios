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

final class FilterTreeGeneratorTests: XCTestCase {

    private var generator: FilterTreeGenerator!

    override func setUp() {
        super.setUp()
        let types: [String: String] = [
            "country": "STRING", "age": "INTEGER", "appVersion": "VERSION", "premium": "BOOLEAN",
            "score": "DECIMAL", "ipAddress": "IP_ADDR", "email": "STRING", "userId": "STRING"
        ]
        generator = FilterTreeGenerator(fieldDataTypeCache: types)
    }

    private func tree(_ json: String) -> IFilter {
        generator.filterTree(json, isRootTagPresent: true, rejectOnParseError: false)
    }

    func testEqualsOperator() {
        let f = tree(#"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("US", forKey: "country")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("UK", forKey: "country")))
    }

    func testNotEqualsOperator() {
        let f = tree(#"{"criteria": {"attr": "country", "operator": "NE", "val": "US"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("UK", forKey: "country")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("US", forKey: "country")))
    }

    func testGreaterThanOperator() {
        let f = tree(#"{"criteria": {"attr": "age", "operator": "GT", "val": 18}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("16", forKey: "age")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("18", forKey: "age")))
    }

    func testGreaterThanOrEqualsOperator() {
        let f = tree(#"{"criteria": {"attr": "age", "operator": "GE", "val": 18}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("18", forKey: "age")))
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func testInOperator() {
        let f = tree(#"{"criteria": {"attr": "country", "operator": "IN", "val": ["US", "CA", "UK"]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("US", forKey: "country")))
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("UK", forKey: "country")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("FR", forKey: "country")))
    }

    func testBetweenOperator() {
        let f = tree(#"{"criteria": {"attr": "age", "operator": "BW", "val": [18, 65]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("30", forKey: "age")))
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("18", forKey: "age")))
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("65", forKey: "age")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("17", forKey: "age")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("66", forKey: "age")))
    }

    func testContainsOperator() {
        let f = tree(#"{"criteria": {"attr": "email", "operator": "CT", "val": "@adobe.com"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("user@adobe.com", forKey: "email")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("user@gmail.com", forKey: "email")))
    }

    func testStartsWithOperator() {
        let f = tree(#"{"criteria": {"attr": "userId", "operator": "SW", "val": "PREMIUM_"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("PREMIUM_12345", forKey: "userId")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("USER_12345", forKey: "userId")))
    }

    func testExistsOperator() {
        let f = tree(#"{"criteria": {"attr": "email", "operator": "EX", "val": true}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("user@test.com", forKey: "email")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("John", forKey: "name")))
    }

    func testAndOperator() {
        let f = tree(#"{"criteria": {"and": [{"attr": "country", "operator": "EQ", "val": "US"},{"attr": "age", "operator": "GT", "val": 18}]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("US", forKey: "country").addAttribute("25", forKey: "age")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("US", forKey: "country").addAttribute("16", forKey: "age")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("UK", forKey: "country").addAttribute("25", forKey: "age")))
    }

    func testOrOperator() {
        let f = tree(#"{"criteria": {"or": [{"attr": "country", "operator": "EQ", "val": "US"},{"attr": "premium", "operator": "EQ", "val": true}]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("US", forKey: "country")))
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("UK", forKey: "country").addAttribute("true", forKey: "premium")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("UK", forKey: "country").addAttribute("false", forKey: "premium")))
    }

    func testNotOperator() {
        let f = tree(#"{"criteria": {"not": [{"attr": "banned", "operator": "EQ", "val": true}]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("false", forKey: "banned")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("true", forKey: "banned")))
    }

    func testNestedLogicalOperators() {
        let f = tree(#"{"criteria": {"and": [{"attr": "country", "operator": "EQ", "val": "US"},{"or": [{"attr": "age", "operator": "GT", "val": 21},{"attr": "premium", "operator": "EQ", "val": true}]}]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("US", forKey: "country").addAttribute("30", forKey: "age").addAttribute("false", forKey: "premium")))
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("US", forKey: "country").addAttribute("18", forKey: "age").addAttribute("true", forKey: "premium")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("US", forKey: "country").addAttribute("18", forKey: "age").addAttribute("false", forKey: "premium")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("UK", forKey: "country").addAttribute("25", forKey: "age")))
    }

    func testVersionGreaterThan() {
        let f = tree(#"{"criteria": {"attr": "appVersion", "operator": "VERSION_GT", "val": "2.0.0"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("2.1.0", forKey: "appVersion")))
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("2.0.1", forKey: "appVersion")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("2.0.0", forKey: "appVersion")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("1.9.9", forKey: "appVersion")))
    }

    func testCidrMatching() {
        let f = tree(#"{"criteria": {"attr": "ipAddress", "operator": "IPO", "val": "192.168.1.0/24"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("192.168.1.100", forKey: "ipAddress")))
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("192.168.2.100", forKey: "ipAddress")))
    }

    func testEmptyCriteria() {
        let f = tree("")
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("value", forKey: "anything")))
    }

    func testNullCriteria() {
        let f = tree("null")
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("value", forKey: "anything")))
    }

    func testStrictModeRejectsPrimitiveCriteriaConfigValue() {
        let criteria = #"{"criteria": true}"#
        let strict = generator.filterTree(criteria, isRootTagPresent: true, rejectOnParseError: true)
        let lenient = generator.filterTree(criteria, isRootTagPresent: true, rejectOnParseError: false)
        let user = UserAttributes().addAttribute("US", forKey: "country")
        XCTAssertFalse(strict.isValid(user))
        XCTAssertTrue(lenient.isValid(user))
    }

    func testPerformanceLocalEvaluation() {
        let criteria = #"{"criteria": {"and": [{"attr": "country", "operator": "IN", "val": ["US", "CA", "UK", "DE", "FR"]},{"attr": "age", "operator": "BW", "val": [18, 65]},{"attr": "platform", "operator": "EQ", "val": "Android"},{"attr": "appVersion", "operator": "VERSION_GT", "val": "1.0.0"}]}}"#
        let gen = FilterTreeGenerator(fieldDataTypeCache: [
            "country": "STRING", "age": "INTEGER", "platform": "STRING", "appVersion": "VERSION"
        ])
        let filter = gen.filterTree(criteria, isRootTagPresent: true, rejectOnParseError: false)
        let user = UserAttributes().addAttribute("US", forKey: "country").addAttribute("30", forKey: "age").addAttribute("Android", forKey: "platform").addAttribute("2.5.0", forKey: "appVersion")
        for _ in 0..<100 { _ = filter.isValid(user) }
        let iterations = 10_000
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { _ = filter.isValid(user) }
        let micros = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000.0 / Double(iterations)
        XCTAssertLessThan(micros, 500, "avg eval should stay well under 500µs on CI-class hardware")
    }
}
