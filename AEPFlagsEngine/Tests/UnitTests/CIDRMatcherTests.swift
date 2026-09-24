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

final class CIDRMatcherTests: XCTestCase {

    func testCidr24Match() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "192.168.1.0/24"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "192.168.1.100", cidr: "192.168.1.0/24"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "192.168.1.254", cidr: "192.168.1.0/24"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.2.1", cidr: "192.168.1.0/24"))
    }

    func testCidr16Match() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "10.0.0.1", cidr: "10.0.0.0/16"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "10.0.255.255", cidr: "10.0.0.0/16"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "10.1.0.1", cidr: "10.0.0.0/16"))
    }

    func testCidr8Match() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "10.1.2.3", cidr: "10.0.0.0/8"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "10.255.255.255", cidr: "10.0.0.0/8"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "11.0.0.1", cidr: "10.0.0.0/8"))
    }

    func testExactIpMatch() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "192.168.1.1"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.2", cidr: "192.168.1.1"))
    }

    func testCidr32Match() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "192.168.1.1/32"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.2", cidr: "192.168.1.1/32"))
    }

    func testCidr0Match() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "0.0.0.0/0"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "10.0.0.1", cidr: "0.0.0.0/0"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "255.255.255.255", cidr: "0.0.0.0/0"))
    }

    func testNullValues() {
        XCTAssertFalse(CIDRMatcher.matches(ip: nil, cidr: "192.168.1.0/24"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.1", cidr: nil))
        XCTAssertFalse(CIDRMatcher.matches(ip: nil, cidr: nil))
    }

    func testInvalidCidrFormat() {
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "invalid"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "192.168.1.0/33"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.1", cidr: "192.168.1.0/-1"))
    }

    func testInvalidIpFormat() {
        XCTAssertFalse(CIDRMatcher.matches(ip: "invalid", cidr: "192.168.1.0/24"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1", cidr: "192.168.1.0/24"))
        XCTAssertFalse(CIDRMatcher.matches(ip: "192.168.1.256", cidr: "192.168.1.0/24"))
    }

    func testIpComparison() {
        XCTAssertEqual(CIDRMatcher.compareIPAddress("192.168.1.1", "192.168.1.1"), 0)
        XCTAssertTrue(CIDRMatcher.compareIPAddress("192.168.1.2", "192.168.1.1") > 0)
        XCTAssertTrue(CIDRMatcher.compareIPAddress("192.168.1.1", "192.168.1.2") < 0)
        XCTAssertTrue(CIDRMatcher.compareIPAddress("192.168.2.1", "192.168.1.255") > 0)
    }

    func testCorporateRanges() {
        XCTAssertTrue(CIDRMatcher.matches(ip: "10.0.0.1", cidr: "10.0.0.0/8"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "172.16.0.1", cidr: "172.16.0.0/12"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "192.168.0.1", cidr: "192.168.0.0/16"))
        XCTAssertTrue(CIDRMatcher.matches(ip: "127.0.0.1", cidr: "127.0.0.0/8"))
    }
}
