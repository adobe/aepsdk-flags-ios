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
import FlagsEngine
import XCTest

class GetFeatureRequestFactoryTests: XCTestCase {
    func testCreate_includesContextWhenProvided() {
        let request = GetFeatureRequestFactory.create(
            context: ["region": ["US"]],
            identityMap: nil
        )
        XCTAssertEqual(["US"], request.context["region"])
        XCTAssertTrue(request.identityMap.isEmpty)
    }

    func testCreate_omitsIdentityMapWhenNilOrEmpty() {
        let withoutMap = GetFeatureRequestFactory.create(context: nil, identityMap: nil)
        XCTAssertTrue(withoutMap.identityMap.isEmpty)

        let emptyMap = GetFeatureRequestFactory.create(context: nil, identityMap: [:])
        XCTAssertTrue(emptyMap.identityMap.isEmpty)
    }

    func testCreate_passesIdentityMapToEngine() {
        let identityMap: [String: [[String: Any]]] = [
            "ECID": [[
                IdentityMapMarshaller.keyId: "ecid-123",
                IdentityMapMarshaller.keyPrimary: true,
                IdentityMapMarshaller.keyAuthenticatedState: "ambiguous"
            ]]
        ]

        let request = GetFeatureRequestFactory.create(context: nil, identityMap: identityMap)
        let ecidEntries = request.identityMap["ECID"]
        XCTAssertEqual("ecid-123", ecidEntries?.first?[IdentityMapMarshaller.keyId] as? String)
        XCTAssertEqual(true, ecidEntries?.first?[IdentityMapMarshaller.keyPrimary] as? Bool)
    }
}
