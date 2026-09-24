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
@testable import AEPCore
import XCTest

class EdgeIdentityFetcherTests: XCTestCase {
    private var runtime: TestableExtensionRuntime!
    private var fetcher: EdgeIdentityFetcher!

    override func setUp() {
        runtime = TestableExtensionRuntime()
        fetcher = EdgeIdentityFetcher()
    }

    private func setEdgeIdentitySharedState(_ value: [String: Any]?, status: SharedStateStatus) {
        runtime.mockedSharedStates[FlagConstants.EdgeIdentity.extensionName] =
            SharedStateResult(status: status, value: value)
    }

    func testFetchIdentityMap_returnsParsedMapWhenSharedStateSet() {
        let xdmState: [String: Any] = [
            IdentityMapMarshaller.xdmKeyIdentityMap: [
                "ECID": [[
                    IdentityMapMarshaller.keyId: "ecid-from-shared-state",
                    IdentityMapMarshaller.keyPrimary: true,
                    IdentityMapMarshaller.keyAuthenticatedState: "ambiguous"
                ]]
            ]
        ]
        setEdgeIdentitySharedState(xdmState, status: .set)

        let event = Event(name: "test", type: FlagConstants.EventType.flags, source: FlagConstants.EventSource.requestContent, data: nil)
        let result = fetcher.fetchIdentityMap(extensionRuntime: runtime, event: event)

        XCTAssertEqual("ecid-from-shared-state", result?["ECID"]?.first?[IdentityMapMarshaller.keyId] as? String)
    }

    func testFetchIdentityMap_returnsNilWhenSharedStatePending() {
        setEdgeIdentitySharedState(nil, status: .pending)

        let event = Event(name: "test", type: FlagConstants.EventType.flags, source: FlagConstants.EventSource.requestContent, data: nil)
        XCTAssertNil(fetcher.fetchIdentityMap(extensionRuntime: runtime, event: event))
    }

    func testIsIdentityReady_notRegistered_returnsTrue() {
        let event = Event(name: "test", type: FlagConstants.EventType.flags, source: FlagConstants.EventSource.requestContent, data: nil)
        XCTAssertTrue(fetcher.isIdentityReady(extensionRuntime: runtime, event: event))
    }

    func testIsIdentityReady_pending_returnsFalse() {
        setEdgeIdentitySharedState(nil, status: .pending)
        let event = Event(name: "test", type: FlagConstants.EventType.flags, source: FlagConstants.EventSource.requestContent, data: nil)
        XCTAssertFalse(fetcher.isIdentityReady(extensionRuntime: runtime, event: event))
    }

    func testIsIdentityReady_setEmptyMap_returnsTrue() {
        setEdgeIdentitySharedState([IdentityMapMarshaller.xdmKeyIdentityMap: [:]], status: .set)
        let event = Event(name: "test", type: FlagConstants.EventType.flags, source: FlagConstants.EventSource.requestContent, data: nil)
        XCTAssertTrue(fetcher.isIdentityReady(extensionRuntime: runtime, event: event))
    }
}
