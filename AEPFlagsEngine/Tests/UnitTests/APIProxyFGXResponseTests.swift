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

/// HTTP-layer tests for the combined v2 response through `APIProxy`.
final class APIProxyFGXResponseTests: XCTestCase {

    private let edgeBaseUrl = "http://fgx-proxy.test"
    private let imsOrg = "test-org"
    private let sandboxName = "test-sandbox"
    private let clientId = "fgx-client"
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

    private func proxy() -> APIProxy {
        APIProxy(edgeBaseUrl: edgeBaseUrl, imsOrg: imsOrg, sandboxName: sandboxName, sharedSession: session)
    }

    func testGetFeaturesParsesFGXResponseWithFeatureGroupsAndMetadata() throws {
        let body = FeaturesResponseJsonFixtures.bodyWithSingleFeature("checkout-redesign",
                                                                      ttl: 240,
                                                                      contextVersion: "ctx-proxy-1")
        stub.setFixedBody(body, etag: "\"proxy-etag\"")
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        let response = try proxy().getFeatures(clientId: clientId, contextVersion: nil, etag: nil)

        XCTAssertTrue(response.isChanged)
        XCTAssertEqual(response.etag, "\"proxy-etag\"")
        XCTAssertEqual(response.pollInterval, 240)

        let fgx = try XCTUnwrap(response.fgxResponse)
        XCTAssertEqual(fgx.version, 2)
        XCTAssertEqual(fgx.contextVersion, "ctx-proxy-1")
        XCTAssertEqual(fgx.fieldDataTypeCache["country"], "STRING")
        XCTAssertEqual(fgx.featureGroups.count, 1)
        XCTAssertEqual(fgx.featureGroups[0].features?.first, "checkout-redesign")

        let metadata = fgx.metadataResponse(etag: response.etag, isChanged: true)
        XCTAssertEqual(metadata.contextVersion, "ctx-proxy-1")
    }

    func testNotModifiedResponse() throws {
        stub.enqueue(.notModified(etag: "\"etag-unchanged\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        let response = try proxy().getFeatures(clientId: clientId,
                                             contextVersion: "test-context-v1",
                                             etag: "\"etag-unchanged\"")

        XCTAssertFalse(response.isChanged)
        XCTAssertEqual(response.etag, "\"etag-unchanged\"")
        XCTAssertNil(response.fgxResponse)
        XCTAssertNil(response.featuresResponses)
        XCTAssertNil(response.pollInterval)

        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: "test-context-v1",
                                                      expectedIfNoneMatch: "\"etag-unchanged\"")
    }

    func testGetFeaturesSendsRequiredHeaders() throws {
        var capturedHeaders: [String: String] = [:]
        MockURLProtocol.register(prefix: edgeBaseUrl + FlagConstants.FLAGS_FEATURE_PATH) { req in
            capturedHeaders = req.allHTTPHeaderFields ?? [:]
            let url = req.url!
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: [FlagConstants.Headers.ETAG: "\"new\""])!
            let body = FeaturesResponseJsonFixtures.bodyWithTtlOnly(60)
            return (resp, body.data(using: .utf8))
        }

        _ = try proxy().getFeatures(clientId: clientId, contextVersion: nil, etag: nil)

        XCTAssertEqual(header(capturedHeaders, FlagConstants.Headers.ACCEPT), FlagConstants.Headers.ACCEPT_JSON)
        XCTAssertEqual(header(capturedHeaders, FlagConstants.Headers.IMS_ORG), imsOrg)
        XCTAssertEqual(header(capturedHeaders, FlagConstants.Headers.SANDBOX_NAME), sandboxName)
        XCTAssertNil(header(capturedHeaders, FlagConstants.Headers.IF_NONE_MATCH))
    }

    func testSubsequentRequestSendsContextVersionAndEtag() throws {
        let bodyV1 = FeaturesResponseJsonFixtures.bodyWithSingleFeature("f1", contextVersion: "ctx-v1")
        let bodyV2 = FeaturesResponseJsonFixtures.bodyWithSingleFeature("f2", contextVersion: "ctx-v2")

        stub.enqueue(.ok(bodyV1, etag: "\"etag-1\""), .ok(bodyV2, etag: "\"etag-2\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        let p = proxy()
        _ = try p.getFeatures(clientId: clientId, contextVersion: nil, etag: nil)
        _ = try p.getFeatures(clientId: clientId, contextVersion: "ctx-v1", etag: "\"etag-1\"")

        XCTAssertEqual(stub.requestCount, 2)
        ServiceRequestAssertions.assertFeatureRequest(stub.lastRequest!,
                                                      clientId: clientId,
                                                      expectedContextVersion: "ctx-v1",
                                                      expectedIfNoneMatch: "\"etag-1\"")
    }

    func testUnparseableBodyThrows() {
        stub.enqueue(.ok("not json", etag: "\"etag-bad\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        XCTAssertThrowsError(try proxy().getFeatures(clientId: clientId, contextVersion: nil, etag: nil)) { error in
            guard case FlagClientError.operationFailed(let message, _) = error else {
                return XCTFail("Expected operationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("Failed to parse features response"))
        }
    }

    func testHttpErrorUsesExpectedStatusMessage() {
        stub.enqueue(.init(statusCode: 502, body: nil, etag: "\"err\""))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        XCTAssertThrowsError(try proxy().getFeatures(clientId: clientId, contextVersion: nil, etag: nil)) { error in
            guard case FlagClientError.networkFailure(let statusCode, _) = error else {
                return XCTFail("Expected networkFailure, got \(error)")
            }
            XCTAssertEqual(statusCode, 502)
            XCTAssertEqual(error.localizedDescription, "Request failed with status: 502")
        }
    }

    func testGetFeaturesNullPollIntervalForNonPositiveTtl() throws {
        stub.setFixedBody(FeaturesResponseJsonFixtures.bodyWithTtlOnly(0))
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        let response = try proxy().getFeatures(clientId: clientId, contextVersion: nil, etag: nil)
        XCTAssertNil(response.pollInterval)
    }

    func testFeaturesUrlTargetsCombinedEndpointOnly() throws {
        stub.setFixedBody(FeaturesResponseJsonFixtures.emptyResponse)
        stub.register(edgeBaseUrl: edgeBaseUrl, clientId: clientId)

        _ = try proxy().getFeatures(clientId: clientId, contextVersion: nil, etag: nil)

        XCTAssertEqual(stub.requestCount, 1)
        XCTAssertEqual(stub.requestedPaths.first, FlagConstants.FLAGS_FEATURE_PATH)
    }

    private func header(_ headers: [String: String], _ field: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }
}
