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

final class FilterOperatorCoverageTests: XCTestCase {

    private var generator: FilterTreeGenerator!

    override func setUp() {
        super.setUp()
        let fieldDataTypes: [String: String] = [
            "country": "STRING", "ageInt": "INTEGER", "ageLong": "LONG", "score": "DECIMAL",
            "active": "BOOLEAN", "startDate": "DATE", "updatedAt": "DATE_TIME",
            "appVersion": "VERSION", "ipAddress": "IP_ADDR"
        ]
        generator = FilterTreeGenerator(fieldDataTypeCache: fieldDataTypes)
    }

    private func parse(_ criteria: String) -> IFilter {
        generator.filterTree(criteria, isRootTagPresent: true, rejectOnParseError: false)
    }

    private func attrs(_ key: String, _ value: String) -> UserAttributes {
        UserAttributes().addAttribute(value, forKey: key)
    }

    // MARK: - LT

    func test_integer_lt_matchesLower() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"LT","val":18}}"#)
        XCTAssertTrue(f.isValid(attrs("ageInt", "17")))
        XCTAssertFalse(f.isValid(attrs("ageInt", "18")))
        XCTAssertFalse(f.isValid(attrs("ageInt", "19")))
    }

    func test_long_lt_matchesLower() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"LT","val":1000000}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "999999")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "1000000")))
    }

    func test_decimal_lt_matchesLower() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"LT","val":9.5}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "9.4")))
        XCTAssertFalse(f.isValid(attrs("score", "9.5")))
        XCTAssertFalse(f.isValid(attrs("score", "10.0")))
    }

    func test_date_lt_matchesEarlier() {
        let f = parse(#"{"criteria":{"attr":"startDate","operator":"LT","val":"2025-06-01"}}"#)
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-05-31")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-06-01")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-07-01")))
    }

    func test_dateTime_lt_matchesEarlier() {
        let f = parse(#"{"criteria":{"attr":"updatedAt","operator":"LT","val":"2025-06-01T12:00:00"}}"#)
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-01T11:59:59")))
        XCTAssertFalse(f.isValid(attrs("updatedAt", "2025-06-01T12:00:00")))
        XCTAssertFalse(f.isValid(attrs("updatedAt", "2025-06-01T13:00:00")))
    }

    func test_string_lt_lexicographic() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"LT","val":"US"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "FR")))
        XCTAssertFalse(f.isValid(attrs("country", "US")))
        XCTAssertFalse(f.isValid(attrs("country", "ZA")))
    }

    func test_lt_missingAttribute_returnsFalse() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"LT","val":18}}"#)
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("US", forKey: "country")))
    }

    // MARK: - LE

    func test_integer_le_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"LE","val":18}}"#)
        XCTAssertTrue(f.isValid(attrs("ageInt", "17")))
        XCTAssertTrue(f.isValid(attrs("ageInt", "18")))
        XCTAssertFalse(f.isValid(attrs("ageInt", "19")))
    }

    func test_long_le_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"LE","val":1000000}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "999999")))
        XCTAssertTrue(f.isValid(attrs("ageLong", "1000000")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "1000001")))
    }

    func test_decimal_le_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"LE","val":9.5}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "9.4")))
        XCTAssertTrue(f.isValid(attrs("score", "9.5")))
        XCTAssertFalse(f.isValid(attrs("score", "9.6")))
    }

    func test_date_le_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"startDate","operator":"LE","val":"2025-06-01"}}"#)
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-05-31")))
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-06-01")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-06-02")))
    }

    func test_dateTime_le_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"updatedAt","operator":"LE","val":"2025-06-01T12:00:00"}}"#)
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-01T11:59:59")))
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-01T12:00:00")))
        XCTAssertFalse(f.isValid(attrs("updatedAt", "2025-06-01T12:00:01")))
    }

    // MARK: - EQ / NE

    func test_integer_eq() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"EQ","val":25}}"#)
        XCTAssertTrue(f.isValid(attrs("ageInt", "25")))
        XCTAssertFalse(f.isValid(attrs("ageInt", "26")))
    }

    func test_integer_ne() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"NE","val":25}}"#)
        XCTAssertTrue(f.isValid(attrs("ageInt", "26")))
        XCTAssertFalse(f.isValid(attrs("ageInt", "25")))
    }

    func test_long_eq() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"EQ","val":9999999999}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "9999999999")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "9999999998")))
    }

    func test_long_ne() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"NE","val":9999999999}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "9999999998")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "9999999999")))
    }

    func test_decimal_eq() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"EQ","val":7.5}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "7.5")))
        XCTAssertFalse(f.isValid(attrs("score", "7.6")))
    }

    func test_decimal_ne() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"NE","val":7.5}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "7.6")))
        XCTAssertFalse(f.isValid(attrs("score", "7.5")))
    }

    func test_boolean_eq_true() {
        let f = parse(#"{"criteria":{"attr":"active","operator":"EQ","val":true}}"#)
        XCTAssertTrue(f.isValid(attrs("active", "true")))
        XCTAssertFalse(f.isValid(attrs("active", "false")))
    }

    func test_boolean_ne() {
        let f = parse(#"{"criteria":{"attr":"active","operator":"NE","val":true}}"#)
        XCTAssertTrue(f.isValid(attrs("active", "false")))
        XCTAssertFalse(f.isValid(attrs("active", "true")))
    }

    func test_date_eq() {
        let f = parse(#"{"criteria":{"attr":"startDate","operator":"EQ","val":"2025-06-15"}}"#)
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-06-15")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-06-16")))
    }

    func test_date_ne() {
        let f = parse(#"{"criteria":{"attr":"startDate","operator":"NE","val":"2025-06-15"}}"#)
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-06-16")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-06-15")))
    }

    func test_ne_missingAttribute_returnsTrue() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"NE","val":25}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("US", forKey: "country")))
    }

    // MARK: - GT / GE (dates)

    func test_date_gt_matchesLater() {
        let f = parse(#"{"criteria":{"attr":"startDate","operator":"GT","val":"2025-06-01"}}"#)
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-06-02")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-06-01")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-05-31")))
    }

    func test_date_ge_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"startDate","operator":"GE","val":"2025-06-01"}}"#)
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-06-01")))
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-06-02")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2025-05-31")))
    }

    func test_dateTime_gt_matchesLater() {
        let f = parse(#"{"criteria":{"attr":"updatedAt","operator":"GT","val":"2025-06-01T12:00:00"}}"#)
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-01T12:00:01")))
        XCTAssertFalse(f.isValid(attrs("updatedAt", "2025-06-01T12:00:00")))
    }

    func test_dateTime_ge_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"updatedAt","operator":"GE","val":"2025-06-01T12:00:00"}}"#)
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-01T12:00:00")))
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-01T12:00:01")))
        XCTAssertFalse(f.isValid(attrs("updatedAt", "2025-06-01T11:59:59")))
    }

    // MARK: - BW

    func test_long_bw_inclusive() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"BW","val":[1000,9000]}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "5000")))
        XCTAssertTrue(f.isValid(attrs("ageLong", "1000")))
        XCTAssertTrue(f.isValid(attrs("ageLong", "9000")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "999")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "9001")))
    }

    func test_decimal_bw_inclusive() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"BW","val":[5.0,9.5]}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "7.0")))
        XCTAssertTrue(f.isValid(attrs("score", "5.0")))
        XCTAssertTrue(f.isValid(attrs("score", "9.5")))
        XCTAssertFalse(f.isValid(attrs("score", "4.9")))
        XCTAssertFalse(f.isValid(attrs("score", "9.6")))
    }

    func test_date_bw_inclusive() {
        let f = parse(#"{"criteria":{"attr":"startDate","operator":"BW","val":["2025-01-01","2025-12-31"]}}"#)
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-06-15")))
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-01-01")))
        XCTAssertTrue(f.isValid(attrs("startDate", "2025-12-31")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2024-12-31")))
        XCTAssertFalse(f.isValid(attrs("startDate", "2026-01-01")))
    }

    func test_dateTime_bw_inclusive() {
        let f = parse(#"{"criteria":{"attr":"updatedAt","operator":"BW","val":["2025-06-01T00:00:00","2025-06-30T23:59:59"]}}"#)
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-15T12:00:00")))
        XCTAssertTrue(f.isValid(attrs("updatedAt", "2025-06-01T00:00:00")))
        XCTAssertFalse(f.isValid(attrs("updatedAt", "2025-05-31T23:59:59")))
        XCTAssertFalse(f.isValid(attrs("updatedAt", "2025-07-01T00:00:00")))
    }

    // MARK: - IN / NOT_IN

    func test_string_notIn_matchesAbsent() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"NOT_IN","val":["US","CA"]}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "UK")))
        XCTAssertFalse(f.isValid(attrs("country", "US")))
        XCTAssertFalse(f.isValid(attrs("country", "CA")))
    }

    func test_integer_in() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"IN","val":[18,21,25]}}"#)
        XCTAssertTrue(f.isValid(attrs("ageInt", "21")))
        XCTAssertFalse(f.isValid(attrs("ageInt", "20")))
    }

    func test_integer_notIn() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"NOT_IN","val":[18,21,25]}}"#)
        XCTAssertTrue(f.isValid(attrs("ageInt", "20")))
        XCTAssertFalse(f.isValid(attrs("ageInt", "21")))
    }

    func test_boolean_in() {
        let f = parse(#"{"criteria":{"attr":"active","operator":"IN","val":[true]}}"#)
        XCTAssertTrue(f.isValid(attrs("active", "true")))
        XCTAssertFalse(f.isValid(attrs("active", "false")))
    }

    func test_notIn_missingAttribute_returnsTrue() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"NOT_IN","val":["US","CA"]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    // MARK: - String operators

    func test_notContains_matchesAbsent() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"NOT_CONTAINS","val":"US"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "France")))
        XCTAssertFalse(f.isValid(attrs("country", "US_WEST")))
    }

    func test_notContains_missingAttribute_returnsTrue() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"NOT_CONTAINS","val":"US"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_endsWith_matchesSuffix() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"EW","val":".com"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "adobe.com")))
        XCTAssertFalse(f.isValid(attrs("country", "adobe.org")))
    }

    func test_endsWith_caseInsensitive() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"EW","val":".COM"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "adobe.com")))
    }

    func test_like_percentWildcard() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"LK","val":"adobe%"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "adobe_express")))
        XCTAssertTrue(f.isValid(attrs("country", "adobe")))
        XCTAssertFalse(f.isValid(attrs("country", "my_adobe")))
    }

    func test_like_underscoreWildcard() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"LK","val":"US_"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "USA")))
        XCTAssertFalse(f.isValid(attrs("country", "US")))
        XCTAssertFalse(f.isValid(attrs("country", "USAA")))
    }

    func test_like_caseInsensitive() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"LK","val":"ADOBE%"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "adobe_express")))
    }

    func test_regex_matchesPattern() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"RE","val":"[A-Z]{2}"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "US")))
        XCTAssertTrue(f.isValid(attrs("country", "CA")))
        XCTAssertFalse(f.isValid(attrs("country", "USA")))
        XCTAssertFalse(f.isValid(attrs("country", "us")))
    }

    func test_regex_complexPattern() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"RE","val":"^\\d{3}-\\d{4}$"}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "123-4567")))
        XCTAssertFalse(f.isValid(attrs("country", "12-4567")))
    }

    func test_regex_invalidPattern_returnsFalse() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"RE","val":"[invalid"}}"#)
        XCTAssertFalse(f.isValid(attrs("country", "US")))
    }

    // MARK: - CEQ

    func test_ceq_exactSetMatch() {
        let filter = Filter(key: "tags", value: ["a", "b", "c"], comparator: .ceq, dataType: .string)
        let user = UserAttributes()
        _ = user.addAttribute(values: ["a", "b", "c"], forKey: "tags")
        XCTAssertTrue(filter.isValid(user))
    }

    func test_ceq_differentSize_returnsFalse() {
        let filter = Filter(key: "tags", value: ["a", "b"], comparator: .ceq, dataType: .string)
        let user = UserAttributes()
        _ = user.addAttribute(values: ["a", "b", "c"], forKey: "tags")
        XCTAssertFalse(filter.isValid(user))
    }

    func test_ceq_differentValues_returnsFalse() {
        let filter = Filter(key: "tags", value: ["a", "b", "d"], comparator: .ceq, dataType: .string)
        let user = UserAttributes()
        _ = user.addAttribute(values: ["a", "b", "c"], forKey: "tags")
        XCTAssertFalse(filter.isValid(user))
    }

    func test_ceq_orderIndependent() {
        let filter = Filter(key: "tags", value: ["c", "a", "b"], comparator: .ceq, dataType: .string)
        let user = UserAttributes()
        _ = user.addAttribute(values: ["a", "b", "c"], forKey: "tags")
        XCTAssertTrue(filter.isValid(user))
    }

    func test_ceq_caseInsensitive() {
        let filter = Filter(key: "tags", value: ["US", "CA"], comparator: .ceq, dataType: .string)
        let user = UserAttributes()
        _ = user.addAttribute(values: ["us", "ca"], forKey: "tags")
        XCTAssertTrue(filter.isValid(user))
    }

    // MARK: - VERSION

    func test_versionEq_exact() {
        let f = parse(#"{"criteria":{"attr":"appVersion","operator":"VERSION_EQ","val":"2.0.0"}}"#)
        XCTAssertTrue(f.isValid(attrs("appVersion", "2.0.0")))
        XCTAssertFalse(f.isValid(attrs("appVersion", "2.0.1")))
        XCTAssertFalse(f.isValid(attrs("appVersion", "1.9.9")))
    }

    func test_versionEq_paddedSegments() {
        let f = parse(#"{"criteria":{"attr":"appVersion","operator":"VERSION_EQ","val":"2.0"}}"#)
        XCTAssertTrue(f.isValid(attrs("appVersion", "2.0.0")))
    }

    func test_versionLt_matchesLower() {
        let f = parse(#"{"criteria":{"attr":"appVersion","operator":"VERSION_LT","val":"2.0.0"}}"#)
        XCTAssertTrue(f.isValid(attrs("appVersion", "1.9.9")))
        XCTAssertTrue(f.isValid(attrs("appVersion", "1.0.0")))
        XCTAssertFalse(f.isValid(attrs("appVersion", "2.0.0")))
        XCTAssertFalse(f.isValid(attrs("appVersion", "2.0.1")))
    }

    func test_versionGe_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"appVersion","operator":"VERSION_GE","val":"2.0.0"}}"#)
        XCTAssertTrue(f.isValid(attrs("appVersion", "2.0.0")))
        XCTAssertTrue(f.isValid(attrs("appVersion", "2.0.1")))
        XCTAssertTrue(f.isValid(attrs("appVersion", "3.0.0")))
        XCTAssertFalse(f.isValid(attrs("appVersion", "1.9.9")))
    }

    func test_versionLe_includesBoundary() {
        let f = parse(#"{"criteria":{"attr":"appVersion","operator":"VERSION_LE","val":"2.0.0"}}"#)
        XCTAssertTrue(f.isValid(attrs("appVersion", "2.0.0")))
        XCTAssertTrue(f.isValid(attrs("appVersion", "1.9.9")))
        XCTAssertFalse(f.isValid(attrs("appVersion", "2.0.1")))
    }

    func test_versionGt_confirmed() {
        let f = parse(#"{"criteria":{"attr":"appVersion","operator":"VERSION_GT","val":"2.0.0"}}"#)
        XCTAssertTrue(f.isValid(attrs("appVersion", "2.0.1")))
        XCTAssertFalse(f.isValid(attrs("appVersion", "2.0.0")))
    }

    func test_version_numericSuffixStripped() {
        let f = parse(#"{"criteria":{"attr":"appVersion","operator":"VERSION_GT","val":"2.0.0"}}"#)
        XCTAssertTrue(f.isValid(attrs("appVersion", "2.1-SNAPSHOT")))
    }

    // MARK: - EXISTS

    func test_ex_trueExpectsPresence_present() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"EX","val":true}}"#)
        XCTAssertTrue(f.isValid(attrs("country", "US")))
    }

    func test_ex_trueExpectsPresence_absent() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"EX","val":true}}"#)
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_ex_falseExpectsAbsence_absent() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"EX","val":false}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_ex_falseExpectsAbsence_present() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"EX","val":false}}"#)
        XCTAssertFalse(f.isValid(attrs("country", "US")))
    }

    // MARK: - Missing-attribute semantics

    func test_eq_missingAttribute_returnsFalse() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"EQ","val":"US"}}"#)
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_gt_missingAttribute_returnsFalse() {
        let f = parse(#"{"criteria":{"attr":"ageInt","operator":"GT","val":18}}"#)
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("US", forKey: "country")))
    }

    func test_in_missingAttribute_returnsFalse() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"IN","val":["US","CA"]}}"#)
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_ne_missingAttribute_returnsTrue_dup() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"NE","val":"US"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_notIn_missingAttribute_returnsTrue_dup() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"NOT_IN","val":["US","CA"]}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_notContains_missingAttribute_returnsTrue_dup() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"NOT_CONTAINS","val":"US"}}"#)
        XCTAssertTrue(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_ct_missingAttribute_returnsFalse() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"CT","val":"US"}}"#)
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    func test_sw_missingAttribute_returnsFalse() {
        let f = parse(#"{"criteria":{"attr":"country","operator":"SW","val":"US"}}"#)
        XCTAssertFalse(f.isValid(UserAttributes().addAttribute("25", forKey: "age")))
    }

    // MARK: - LONG / DECIMAL

    func test_long_gt() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"GT","val":100}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "101")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "100")))
    }

    func test_long_ge() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"GE","val":100}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "100")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "99")))
    }

    func test_long_in() {
        let f = parse(#"{"criteria":{"attr":"ageLong","operator":"IN","val":[10,20,30]}}"#)
        XCTAssertTrue(f.isValid(attrs("ageLong", "20")))
        XCTAssertFalse(f.isValid(attrs("ageLong", "25")))
    }

    func test_decimal_gt() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"GT","val":5.5}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "5.6")))
        XCTAssertFalse(f.isValid(attrs("score", "5.5")))
    }

    func test_decimal_ge() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"GE","val":5.5}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "5.5")))
        XCTAssertFalse(f.isValid(attrs("score", "5.4")))
    }

    func test_decimal_in() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"IN","val":[1.5,2.5,3.5]}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "2.5")))
        XCTAssertFalse(f.isValid(attrs("score", "2.6")))
    }

    func test_decimal_notIn() {
        let f = parse(#"{"criteria":{"attr":"score","operator":"NOT_IN","val":[1.5,2.5]}}"#)
        XCTAssertTrue(f.isValid(attrs("score", "3.0")))
        XCTAssertFalse(f.isValid(attrs("score", "1.5")))
    }
}
