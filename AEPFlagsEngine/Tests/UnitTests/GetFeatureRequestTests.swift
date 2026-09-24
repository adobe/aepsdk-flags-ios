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

final class GetFeatureRequestTests: XCTestCase {

    func testBuildWithoutFieldsReturnsEmptyMaps() {
        let request = GetFeatureRequest.builder().build()
        XCTAssertTrue(request.context.isEmpty)
        XCTAssertTrue(request.identityMap.isEmpty)
    }

    func testDefaultRequestIsEmpty() {
        XCTAssertTrue(GetFeatureRequest.defaultRequest.context.isEmpty)
        XCTAssertTrue(GetFeatureRequest.defaultRequest.identityMap.isEmpty)
    }

    func testContextIsolatedFromOuterMapMutation() {
        var context: [String: [String]] = ["country": ["US"]]
        let request = GetFeatureRequest.builder().context(context).build()
        context["region"] = ["VA7"]
        context.removeValue(forKey: "country")
        XCTAssertEqual(request.context["country"], ["US"])
        XCTAssertEqual(request.context.count, 1)
    }

    func testContextIsolatedFromInnerListMutation() {
        var countries = ["US"]
        let context: [String: [String]] = ["country": countries]
        let request = GetFeatureRequest.builder().context(context).build()
        countries.append("CA")
        XCTAssertEqual(request.context["country"], ["US"])
    }

    func testIdentityMapIsolatedFromOuterMapMutation() {
        var entry = IdentityMapTestHelpers.identityEntry(id: "ecid-123", primary: true)
        var identityMap: [String: [[String: Any]]] = ["ECID": [entry]]
        let request = GetFeatureRequest.builder().identityMap(identityMap).build()
        identityMap["Email"] = [IdentityMapTestHelpers.identityEntry(id: "other", primary: false)]
        identityMap.removeValue(forKey: "ECID")
        XCTAssertEqual(request.identityMap.count, 1)
        XCTAssertEqual(request.identityMap["ECID"]?.first?[FlagConstants.IdentityMap.ENTRY_KEY_ID] as? String, "ecid-123")
    }

    func testIdentityMapIsolatedFromInnerListMutation() {
        var entries = [IdentityMapTestHelpers.identityEntry(id: "ecid-123", primary: true)]
        var identityMap: [String: [[String: Any]]] = ["ECID": entries]
        let request = GetFeatureRequest.builder().identityMap(identityMap).build()
        entries.append(IdentityMapTestHelpers.identityEntry(id: "other", primary: false))
        XCTAssertEqual(request.identityMap["ECID"]?.count, 1)
        XCTAssertEqual(request.identityMap["ECID"]?.first?[FlagConstants.IdentityMap.ENTRY_KEY_ID] as? String, "ecid-123")
    }

    func testIdentityMapIsolatedFromEntryMutation() {
        var entry = IdentityMapTestHelpers.identityEntry(id: "ecid-123", primary: true)
        let identityMap: [String: [[String: Any]]] = ["ECID": [entry]]
        let request = GetFeatureRequest.builder().identityMap(identityMap).build()
        entry[FlagConstants.IdentityMap.ENTRY_KEY_ID] = "mutated"
        XCTAssertEqual(request.identityMap["ECID"]?.first?[FlagConstants.IdentityMap.ENTRY_KEY_ID] as? String, "ecid-123")
    }

    func testIdentityMapRetainsEmptyEntryMaps() {
        let identityMap: [String: [[String: Any]]] = ["ECID": [[:]]]
        let request = GetFeatureRequest.builder().identityMap(identityMap).build()
        XCTAssertEqual(request.identityMap["ECID"]?.count, 1)
        XCTAssertTrue(request.identityMap["ECID"]?.first?.isEmpty ?? false)
    }

    func testContextGetterIsImmutable() {
        let request = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        XCTAssertEqual(request.context["country"], ["US"])
        // `let` prevents reassignment of top-level keys from outside the type.
        XCTAssertEqual(request.context.count, 1)
    }
}
