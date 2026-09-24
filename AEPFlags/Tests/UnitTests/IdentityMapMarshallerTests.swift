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
import XCTest

class IdentityMapMarshallerTests: XCTestCase {
    private func ecidItem(id: String, primary: Bool = true, authenticatedState: String = "ambiguous") -> [String: Any] {
        [
            IdentityMapMarshaller.keyId: id,
            IdentityMapMarshaller.keyPrimary: primary,
            IdentityMapMarshaller.keyAuthenticatedState: authenticatedState
        ]
    }

    private func edgeIdentityXdmSharedState(namespaces: [String: Any]) -> [String: Any] {
        [IdentityMapMarshaller.xdmKeyIdentityMap: namespaces]
    }

    func testFromXDMStateMap_nullOrEmpty_returnsNil() {
        XCTAssertNil(IdentityMapMarshaller.fromXDMStateMap(nil))
        XCTAssertNil(IdentityMapMarshaller.fromXDMStateMap([:]))
    }

    func testFromXDMStateMap_parsesValidECID() {
        let state = edgeIdentityXdmSharedState(namespaces: [
            "ECID": [ecidItem(id: "ecid-123")]
        ])

        let result = IdentityMapMarshaller.fromXDMStateMap(state)
        XCTAssertEqual(1, result?.count)
        XCTAssertEqual("ecid-123", result?["ECID"]?.first?[IdentityMapMarshaller.keyId] as? String)
        XCTAssertEqual(true, result?["ECID"]?.first?[IdentityMapMarshaller.keyPrimary] as? Bool)
        XCTAssertEqual("ambiguous", result?["ECID"]?.first?[IdentityMapMarshaller.keyAuthenticatedState] as? String)
    }

    func testFromXDMStateMap_missingIdentityMapWrapper_returnsNil() {
        XCTAssertNil(IdentityMapMarshaller.fromXDMStateMap(["other": "value"]))
    }

    func testFromXDMStateMap_skipsItemsWithEmptyId() {
        let state = edgeIdentityXdmSharedState(namespaces: [
            "ECID": [[IdentityMapMarshaller.keyId: ""]]
        ])
        XCTAssertNil(IdentityMapMarshaller.fromXDMStateMap(state))
    }

    func testFromXDMStateMap_multipleNamespaces() {
        let state = edgeIdentityXdmSharedState(namespaces: [
            "ECID": [ecidItem(id: "ecid-1")],
            "Email": [ecidItem(id: "user@example.com", primary: false, authenticatedState: "authenticated")]
        ])

        let result = IdentityMapMarshaller.fromXDMStateMap(state)
        XCTAssertEqual(2, result?.count)
        XCTAssertEqual("user@example.com", result?["Email"]?.first?[IdentityMapMarshaller.keyId] as? String)
    }
}
