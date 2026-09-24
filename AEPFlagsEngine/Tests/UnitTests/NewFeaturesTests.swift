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

final class NewFeaturesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FilterPatchesCache.shared.refresh()
    }

    func testIPv6Validation() {
        XCTAssertTrue(CIDRMatcher.isIPv6("2001:db8::1"))
        XCTAssertTrue(CIDRMatcher.isIPv6("::1"))
        XCTAssertTrue(CIDRMatcher.isIPv6("fe80::1"))
        XCTAssertTrue(CIDRMatcher.isIPv6("2001:0db8:0000:0000:0000:0000:0000:0001"))
        XCTAssertTrue(CIDRMatcher.isIPv6("::ffff:192.168.1.1"))
        XCTAssertFalse(CIDRMatcher.isIPv6("192.168.1.1"))
        XCTAssertFalse(CIDRMatcher.isIPv6("invalid"))
        XCTAssertFalse(CIDRMatcher.isIPv6("2001:db8:::1"))
        XCTAssertFalse(CIDRMatcher.isIPv6(nil))
        XCTAssertFalse(CIDRMatcher.isIPv6(""))
    }

    func testIPv6CIDRMatching() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "2001:db8::1", cidr: "2001:db8::/32"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "2001:db8:ffff:ffff::1", cidr: "2001:db8::/32"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "2001:db9::1", cidr: "2001:db8::/32"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "2001:db8:85a3::1", cidr: "2001:db8:85a3::/64"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "2001:db8:85a4::1", cidr: "2001:db8:85a3::/64"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "2001:db8::1", cidr: "2001:db8::1/128"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "2001:db8::2", cidr: "2001:db8::1/128"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "2001:db8::1", cidr: "::/0"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "::1", cidr: "::/0"))
    }

    func testIPv6CompressedNotation() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "::1", cidr: "::1/128"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "fe80::1", cidr: "fe80::/10"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "::ffff:192.168.1.1", cidr: "::ffff:192.168.0.0/112"))
    }

    func testIPv6Comparison() {
        XCTAssertEqual(CIDRMatcher.compareIPAddress("2001:db8::1", "2001:db8::1"), 0)
        XCTAssertLessThan(CIDRMatcher.compareIPAddress("2001:db8::1", "2001:db8::2"), 0)
        XCTAssertGreaterThan(CIDRMatcher.compareIPAddress("2001:db8::2", "2001:db8::1"), 0)
    }

    func testMixedIPVersions() {
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "2001:db8::/32"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "2001:db8::1", cidr: "192.168.1.0/24"))
    }

    func testDateExpressionTodayPlus() throws {
        let v = try DateExpressionValidator().parseExpression("today+5d") as! Int64
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var expected = Date()
        expected = cal.date(byAdding: .day, value: 5, to: expected) ?? expected
        let expMs = Int64(expected.timeIntervalSince1970 * 1000)
        XCTAssertLessThan(abs(v - expMs), 1000)
    }

    func testDateExpressionTodayMinus() throws {
        let v = try DateExpressionValidator().parseExpression("today-3d") as! Int64
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var expected = Date()
        expected = cal.date(byAdding: .day, value: -3, to: expected) ?? expected
        let expMs = Int64(expected.timeIntervalSince1970 * 1000)
        XCTAssertLessThan(abs(v - expMs), 1000)
    }

    func testDateExpressionInvalidFormat() {
        XCTAssertThrowsError(try DateExpressionValidator().parseExpression("invalid"))
    }

    func testExpressionValidatorEnum() {
        let dateValidator = ExpressionValidator.validator(for: .date)
        XCTAssertNotNil(dateValidator)
        XCTAssertEqual(dateValidator?.dataType, .date)
        let dtValidator = ExpressionValidator.validator(for: .dateTime)
        XCTAssertNotNil(dtValidator)
        XCTAssertNil(ExpressionValidator.validator(for: .string))
    }

    func testSupportsExpression() {
        XCTAssertTrue(ExpressionValidator.supports(.date))
        XCTAssertTrue(ExpressionValidator.supports(.dateTime))
        XCTAssertFalse(ExpressionValidator.supports(.string))
        XCTAssertFalse(ExpressionValidator.supports(.integer))
    }

    func testFilterPatchesCacheSingleton() {
        let a = FilterPatchesCache.shared
        let b = FilterPatchesCache.shared
        XCTAssertTrue(a === b)
    }

    func testFilterPatchesCacheAddGet() {
        let f = Filter(key: "country", value: "US", comparator: .eq, dataType: .string)
        FilterPatchesCache.shared.add(f, for: "patch1")
        XCTAssertTrue(FilterPatchesCache.shared.hasPatch(for: "patch1"))
        let retrieved = FilterPatchesCache.shared.patch(for: "patch1")
        XCTAssertFalse(retrieved is EmptyFilter)
    }

    func testFilterPatchesCacheRemove() {
        let f = Filter(key: "country", value: "US", comparator: .eq, dataType: .string)
        FilterPatchesCache.shared.add(f, for: "patchToRemove")
        XCTAssertTrue(FilterPatchesCache.shared.hasPatch(for: "patchToRemove"))
        FilterPatchesCache.shared.remove("patchToRemove")
        XCTAssertFalse(FilterPatchesCache.shared.hasPatch(for: "patchToRemove"))
    }

    func testFilterPatchesCacheEmptyFilter() {
        let result = FilterPatchesCache.shared.patch(for: "nonexistent")
        XCTAssertTrue(result is EmptyFilter)
    }

    func testPatchOperator() {
        let cached = Filter(key: "country", value: "US", comparator: .eq, dataType: .string)
        FilterPatchesCache.shared.add(cached, for: "countryUSPatch")
        let patchFilter = Filter(key: "", value: "countryUSPatch", comparator: .patch, dataType: .string)
        XCTAssertTrue(patchFilter.isPatch)
        let us = UserAttributes().addAttribute("US", forKey: "country")
        let uk = UserAttributes().addAttribute("UK", forKey: "country")
        XCTAssertTrue(patchFilter.isValid(us))
        XCTAssertFalse(patchFilter.isValid(uk))
    }

    func testSelectedValueReference() {
        let filter = Filter(key: "currentCountry", value: "preferredCountry", comparator: .eq,
                            dataType: .string, id: 0, isExpression: false, isSelectedVal: true)
        let ok = UserAttributes().addAttribute("US", forKey: "currentCountry").addAttribute("US", forKey: "preferredCountry")
        let bad = UserAttributes().addAttribute("US", forKey: "currentCountry").addAttribute("UK", forKey: "preferredCountry")
        XCTAssertTrue(filter.isValid(ok))
        XCTAssertFalse(filter.isValid(bad))
    }

    func testExpressionFilter() {
        let tenDays = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let twoDays = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let filter = Filter(key: "cancelDate", value: "today-5d", comparator: .lt,
                             dataType: .date, id: 0, isExpression: true, isSelectedVal: false)
        let oldUser = UserAttributes().addAttribute("\(Int64(tenDays.timeIntervalSince1970 * 1000))", forKey: "cancelDate")
        let recentUser = UserAttributes().addAttribute("\(Int64(twoDays.timeIntervalSince1970 * 1000))", forKey: "cancelDate")
        XCTAssertTrue(filter.isValid(oldUser))
        XCTAssertFalse(filter.isValid(recentUser))
    }

    func testFieldDataTypeCache() {
        let c = FieldDataTypeCache()
        c.setFieldDataType(.string, for: "country").setFieldDataType(.integer, for: "age")
        XCTAssertEqual(c.fieldDataType(for: "country"), .string)
        XCTAssertEqual(c.fieldDataType(for: "age"), .integer)
        XCTAssertNil(c.fieldDataType(for: "nonexistent"))
    }

    func testFieldDataTypeCacheAepMetadata() {
        let c = FieldDataTypeCache()
        c.setAepMetadata(.string, for: "aepField")
        XCTAssertTrue(c.hasAepMetadata(for: "aepField"))
        XCTAssertEqual(c.aepMetadata(for: "aepField"), .string)
        XCTAssertFalse(c.hasAepMetadata(for: "nonexistent"))
    }

    func testFieldDataTypeCacheFieldMetadata() {
        let c = FieldDataTypeCache()
        c.setFieldMetadata(["isBucketizable": "true"], for: "bucket_field")
        XCTAssertEqual(c.fieldMetadata(for: "bucket_field"), ["isBucketizable": "true"])
        XCTAssertNil(c.fieldMetadata(for: "nonexistent"))
    }

    func testIPv6FilterIntegration() {
        let ranges: [Any] = ["2001:db8::/32", "fe80::/10"]
        let filter = Filter(key: "ipAddress", value: ranges, comparator: .ipo, dataType: .ipAddr)
        let inRange = UserAttributes().addAttribute("2001:db8::1", forKey: "ipAddress")
        let out = UserAttributes().addAttribute("2001:db9::1", forKey: "ipAddress")
        XCTAssertTrue(filter.isValid(inRange))
        XCTAssertFalse(filter.isValid(out))
    }

    func testFilterServiceBasicValidation() {
        let fs = FilterService(fieldDataTypeCache: ["country": "STRING"])
        let f = Filter(key: "country", value: "US", comparator: .eq, dataType: .string)
        let us = UserAttributes().addAttribute("US", forKey: "country")
        let uk = UserAttributes().addAttribute("UK", forKey: "country")
        XCTAssertTrue(fs.isValid(us, filter: f))
        XCTAssertFalse(fs.isValid(uk, filter: f))
    }

    func testFilterServiceNullFilter() {
        let fs = FilterService(fieldDataTypeCache: ["country": "STRING"])
        let u = UserAttributes().addAttribute("US", forKey: "country")
        XCTAssertTrue(fs.isValid(u, filter: nil))
    }

    func testMatchesCriteriaVacuousWhenCriteriaAbsent() {
        let fs = FilterService(fieldDataTypeCache: ["country": "STRING"])
        let u = UserAttributes().addAttribute("US", forKey: "country")
        XCTAssertTrue(fs.matches(criteriaJson: nil, userAttributes: u))
        XCTAssertTrue(fs.matches(criteriaJson: "", userAttributes: u))
    }

    func testMatchesCriteriaFailsClosedOnMalformedJson() {
        let fs = FilterService(fieldDataTypeCache: ["country": "STRING"])
        let u = UserAttributes().addAttribute("US", forKey: "country")
        XCTAssertFalse(fs.matches(criteriaJson: "not valid json{{{", userAttributes: u))
    }

    func testContainsAndFilterDelegatorBasic() {
        let fs = FilterService(fieldDataTypeCache: ["plan": "STRING", "status": "STRING"])
        let delegator = ContainsAndFilterDelegator(filterService: fs)
        let nested = Filter(key: "status", value: "active", comparator: .eq, dataType: .string)
        let sub1 = UserAttributes().addAttribute("premium", forKey: "plan").addAttribute("inactive", forKey: "status")
        let sub2 = UserAttributes().addAttribute("basic", forKey: "plan").addAttribute("active", forKey: "status")
        let subs: [Any] = [sub1, sub2]
        XCTAssertTrue(delegator.delegate(stateValue: subs, filterValue: nested, relationalEquality: nil))
    }

    func testContainsAndFilterDelegatorNoMatch() {
        let fs = FilterService(fieldDataTypeCache: ["status": "STRING"])
        let delegator = ContainsAndFilterDelegator(filterService: fs)
        let nested = Filter(key: "status", value: "active", comparator: .eq, dataType: .string)
        let subs: [Any] = [
            UserAttributes().addAttribute("inactive", forKey: "status"),
            UserAttributes().addAttribute("cancelled", forKey: "status")
        ]
        XCTAssertFalse(delegator.delegate(stateValue: subs, filterValue: nested, relationalEquality: nil))
    }

    func testContainsAndFilterDelegatorWithReturnValues() {
        let fs = FilterService(fieldDataTypeCache: ["plan": "STRING", "status": "STRING"])
        let delegator = ContainsAndFilterDelegator(filterService: fs)
        let nested = Filter(key: "status", value: "active", comparator: .eq, dataType: .string)
        let sub1 = UserAttributes().addAttribute("premium", forKey: "plan").addAttribute("active", forKey: "status")
        let subs: [Any] = [sub1]
        let res = delegator.delegateWithReturnValues(stateValue: subs, filterValue: nested, relationalEquality: nil, id: 1, attrId: "subscriptions")
        XCTAssertTrue(res.isValid)
        XCTAssertFalse(res.matchedAttributes.attributes.isEmpty)
    }

    func testContainsAndFilterDelegatorAllReturnValues() {
        let fs = FilterService(fieldDataTypeCache: ["status": "STRING"])
        let delegator = ContainsAndFilterDelegator(filterService: fs)
        let nested = Filter(key: "status", value: "active", comparator: .eq, dataType: .string)
        let subs: [Any] = [
            UserAttributes().addAttribute("active", forKey: "status"),
            UserAttributes().addAttribute("inactive", forKey: "status"),
            UserAttributes().addAttribute("active", forKey: "status")
        ]
        let valid = delegator.delegateWithAllReturnValues(stateValue: subs, filterValue: nested, relationalEquality: nil, id: 1, attrId: "subscriptions")
        XCTAssertEqual(valid.count, 2)
    }

    func testContainsAndFilterDelegatorPreprocess() {
        let fs = FilterService(fieldDataTypeCache: [:])
        let delegator = ContainsAndFilterDelegator(filterService: fs)
        let parent = UserAttributes().addAttribute("123", forKey: "selected_id")
        let sub = UserAttributes().addAttribute("premium", forKey: "plan")
        let subs: [Any] = [sub]
        delegator.preprocessUserAttributes(stateValue: subs, objectToValidate: parent)
        XCTAssertEqual(sub.attribute(forKey: "selected_id"), "123")
    }

    func testUserAttributesMerge() {
        let target = UserAttributes().addAttribute("US", forKey: "country")
        let source = UserAttributes().addAttribute("NYC", forKey: "city").addAttribute("NY", forKey: "state")
        target.addOrUpdate(from: source)
        XCTAssertEqual(target.attribute(forKey: "country"), "US")
        XCTAssertEqual(target.attribute(forKey: "city"), "NYC")
        XCTAssertEqual(target.attribute(forKey: "state"), "NY")
    }
}
