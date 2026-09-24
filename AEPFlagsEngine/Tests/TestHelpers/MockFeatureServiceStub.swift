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

import Foundation
@testable import FlagsEngine

/// Stubs `GET {edgeBaseUrl}/flags/feature` with optional sequential responses.
final class MockFeatureServiceStub {

    struct Response {
        let statusCode: Int
        let body: String?
        let etag: String

        static func ok(_ body: String, etag: String = "\"feature-etag-1\"") -> Response {
            Response(statusCode: 200, body: body, etag: etag)
        }

        static func notModified(etag: String) -> Response {
            Response(statusCode: 304, body: nil, etag: etag)
        }
    }

    private(set) var requestCount = 0
    private(set) var requestedPaths: [String] = []
    private(set) var lastRequest: URLRequest?
    private var responses: [Response] = []
    private var responseIndex = 0

    func reset() {
        requestCount = 0
        requestedPaths.removeAll()
        lastRequest = nil
        responses.removeAll()
        responseIndex = 0
    }

    func setFixedBody(_ body: String, etag: String = "\"feature-etag-1\"") {
        responses = [Response.ok(body, etag: etag)]
        responseIndex = 0
    }

    func enqueueList(_ responses: [Response]) {
        self.responses = responses
        responseIndex = 0
    }

    func enqueue(_ responses: Response...) {
        enqueueList(Array(responses))
    }

    /// Appends responses for subsequent requests (scheduled poll / sequential response tests).
    func append(_ responses: Response...) {
        self.responses.append(contentsOf: responses)
    }

    /// Registers a stub for `GET {edgeBaseUrl}/flags/feature`. `clientId` mirrors the
    /// real API surface but is not used — routing is by URL prefix only.
    func register(edgeBaseUrl: String, clientId _: String) {
        let prefix = edgeBaseUrl + FlagConstants.FLAGS_FEATURE_PATH
        MockURLProtocol.register(prefix: prefix) { [weak self] request in
            guard let self = self else {
                let url = request.url ?? URL(string: "http://invalid")!
                return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
            }

            self.requestCount += 1
            self.lastRequest = request
            if let path = request.url?.path {
                self.requestedPaths.append(path)
            }

            let response = self.nextResponse()
            let url = request.url!
            let resp = HTTPURLResponse(url: url,
                                       statusCode: response.statusCode,
                                       httpVersion: nil,
                                       headerFields: [FlagConstants.Headers.ETAG: response.etag])!
            let data = response.body?.data(using: .utf8)
            return (resp, data)
        }
    }

    private func nextResponse() -> Response {
        guard !responses.isEmpty else {
            return Response(statusCode: 404, body: nil, etag: "\"missing\"")
        }
        let idx = min(responseIndex, responses.count - 1)
        if responseIndex < responses.count {
            responseIndex += 1
        }
        return responses[idx]
    }
}
