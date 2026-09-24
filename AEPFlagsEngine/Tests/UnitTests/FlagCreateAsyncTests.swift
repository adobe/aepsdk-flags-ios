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

final class FlagCreateAsyncTests: XCTestCase {

    private let edgeDomain = "async-create.test"
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

    private func config(clientId: String) throws -> FlagConfiguration {
        stub.setFixedBody(FeaturesResponseJsonFixtures.bodyWithTtlOnly(300), etag: "\"f1\"")
        stub.register(edgeBaseUrl: FeatureServiceUrls.baseUrl(fromEdgeDomain: edgeDomain), clientId: clientId)
        return try FlagConfiguration.builder()
            .edgeDomain(edgeDomain)
            .imsOrg("test-org")
            .sandboxName("test-sandbox")
            .clientId(clientId)
            .urlSession(session)
            .build()
    }

    func testCreateAsyncDefaultQueueNotMainThread() throws {
        let exp = expectation(description: "async create")
        let cfg = try config(clientId: "async-test")
        Flag.createAsync(configuration: cfg) { client, error in
            XCTAssertNil(error)
            XCTAssertNotNil(client)
            XCTAssertTrue(client!.isInitialized)
            XCTAssertFalse(Thread.isMainThread)
            client?.close()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 15)
    }

    func testCreateAsyncRunsOnSuppliedQueue() throws {
        let marker = DispatchSpecificKey<UInt8>()
        let work = DispatchQueue(label: "custom-init-executor")
        work.setSpecific(key: marker, value: 1)
        let exp = expectation(description: "executor create")
        let cfg = try config(clientId: "exec-test")
        Flag.createAsync(configuration: cfg, queue: work) { client, error in
            XCTAssertNil(error)
            XCTAssertEqual(DispatchQueue.getSpecific(key: marker), 1)
            client?.close()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 15)
    }

    func testCreateAsyncNullConfiguration() {
        let exp = expectation(description: "null cfg")
        Flag.createAsync(configuration: nil) { client, error in
            XCTAssertNil(client)
            XCTAssertEqual(error as? FlagInitError, .missingConfiguration)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testCreateAsyncNullWorkQueue() throws {
        let exp = expectation(description: "null work queue")
        let cfg = try config(clientId: "null-exec-test")
        Flag.createAsync(configuration: cfg, requiringWorkQueue: nil) { client, error in
            XCTAssertNil(client)
            guard let err = error as? FlagInitError else {
                XCTFail("expected FlagInitError")
                exp.fulfill()
                return
            }
            guard case .initializationFailed(_, let underlying) = err,
                  let clientError = underlying as? FlagClientError,
                  case .invalidArgument(let message) = clientError else {
                XCTFail("expected invalidArgument underlying error")
                exp.fulfill()
                return
            }
            XCTAssertEqual(message, "Executor is required")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }
}
