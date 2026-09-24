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

final class FlagThreadSafetyTests: XCTestCase {

    private func stubConfig() throws -> FlagConfiguration {
        try FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("test-org")
            .sandboxName("test-sandbox")
            .clientId("thread-test")
            .build()
    }

    func testConcurrentCloseIsIdempotent() throws {
        let client = Flag(configuration: try stubConfig())
        client.testMarkInitializedWithoutNetwork()
        XCTAssertTrue(client.isInitialized)
        DispatchQueue.concurrentPerform(iterations: 32) { _ in client.close() }
        XCTAssertFalse(client.isInitialized)
    }

    func testCloseVisibleToReaders() throws {
        let client = Flag(configuration: try stubConfig())
        client.testMarkInitializedWithoutNetwork()
        DispatchQueue.concurrentPerform(iterations: 17) { i in
            if i == 16 {
                client.close()
            } else {
                for _ in 0..<5000 { _ = client.isInitialized }
            }
        }
        XCTAssertFalse(client.isInitialized)
    }

    func testEvaluationAfterCloseThrowsCleanly() throws {
        let client = Flag(configuration: try stubConfig())
        client.testMarkInitializedWithoutNetwork()
        client.close()
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            for _ in 0..<100 {
                do {
                    _ = try client.isFeatureEnabled("any-flag", for: nil)
                    XCTFail("expected error")
                } catch {
                    XCTAssertTrue(error is FlagClientError)
                }
            }
        }
    }

    func testTwoIndependentInstances() throws {
        let a = Flag(configuration: try stubConfig())
        let b = Flag(configuration: try FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("test-org")
            .sandboxName("test-sandbox")
            .clientId("thread-test")
            .build())
        a.testMarkInitializedWithoutNetwork()
        b.testMarkInitializedWithoutNetwork()
        XCTAssertTrue(a.isInitialized && b.isInitialized)
        a.close()
        XCTAssertFalse(a.isInitialized)
        XCTAssertTrue(b.isInitialized)
        b.close()
        XCTAssertFalse(b.isInitialized)
    }

    func testConcurrentCloseOneClientDoesNotAffectOther() throws {
        let a = Flag(configuration: try stubConfig())
        let b = Flag(configuration: try FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("test-org")
            .sandboxName("test-sandbox")
            .clientId("thread-test")
            .build())
        a.testMarkInitializedWithoutNetwork()
        b.testMarkInitializedWithoutNetwork()
        DispatchQueue.concurrentPerform(iterations: 16) { i in
            if i % 2 == 0 {
                a.close()
            } else {
                for _ in 0..<500 { XCTAssertTrue(b.isInitialized) }
            }
        }
        XCTAssertFalse(a.isInitialized)
        XCTAssertTrue(b.isInitialized)
        b.close()
    }
}
