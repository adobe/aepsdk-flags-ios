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

// Tests register a `URLSession` configured with this `URLProtocol` and stub responses
// by URL prefix.

final class MockURLProtocol: URLProtocol {

    typealias Responder = (URLRequest) -> (HTTPURLResponse, Data?)

    private static let lock = NSLock()
    private static var responders: [(prefix: String, responder: Responder)] = []

    static func register(prefix: String, responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        responders.append((prefix, responder))
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responders.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return responder(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = MockURLProtocol.responder(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func responder(for request: URLRequest) -> Responder? {
        lock.lock(); defer { lock.unlock() }
        guard let urlString = request.url?.absoluteString else { return nil }
        return responders.first(where: { urlString.hasPrefix($0.prefix) })?.responder
    }
}
