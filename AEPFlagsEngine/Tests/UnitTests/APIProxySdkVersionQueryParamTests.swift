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

final class APIProxySdkVersionQueryParamTests: XCTestCase {

    private let imsOrg = "test-org"
    private let sandboxName = "test-sandbox"
    private var session: URLSession!
    private var stub: MockFeatureServiceStub!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        stub = MockFeatureServiceStub()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: cfg)
    }

    override func tearDown() {
        session.finishTasksAndInvalidate()
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testSdkVersionQueryParamAlwaysPresentOnFeatureRequests() throws {
        let edgeBaseUrl = "http://sdk-version.test"
        stub.setFixedBody(FeaturesResponseJsonFixtures.minimalBody(), etag: "\"etag-1\"")
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: "client-a")

        let proxy = APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: session)
        defer { proxy.shutdown() }

        let response = try proxy.getFeatures(clientId: "client-a", contextVersion: nil, etag: nil)
        XCTAssertTrue(response.isChanged)
        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!, clientId: "client-a", expectedContextVersion: nil)
    }

    func testBuildFeatureRequestURLAlwaysIncludesSdkVersionKey() throws {
        let edgeBaseUrl = "http://sdk-version.test"
        let proxy = APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: session)
        defer { proxy.shutdown() }

        let url = try proxy.buildFeatureRequestURL(clientId: "client-a", contextVersion: "ctx-v1")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let names = Set((components?.queryItems ?? []).map { $0.name })
        XCTAssertTrue(names.contains(FlagConstants.Query.SDK_VERSION))

        // With no injected version, the key is present but carries no value.
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertNil(query[FlagConstants.Query.SDK_VERSION] ?? nil)
    }

    func testInjectedSdkVersionSetsQueryParam() throws {
        let edgeBaseUrl = "http://sdk-version.test"
        let injected = "9.9.9-injected"
        let proxy = APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName,
                             sharedSession: session, sdkVersion: injected)
        defer { proxy.shutdown() }

        let url = try proxy.buildFeatureRequestURL(clientId: "client-a", contextVersion: nil)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query[FlagConstants.Query.SDK_VERSION], injected)
    }
}
