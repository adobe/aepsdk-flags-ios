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

final class FlagConfigurationTests: XCTestCase {

    private let testImsOrg = "test-org"
    private let testSandbox = "test-sandbox"
    private let testEdgeDomain = "edge.example.com"

    func testValidBuild() throws {
        let config = try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()
        XCTAssertEqual(config.edgeDomain, testEdgeDomain)
        XCTAssertEqual(config.clientId, "client-a")
    }

    func testEdgeDomainTrimsWhitespace() throws {
        let config = try FlagConfiguration.builder()
            .edgeDomain("  edge.example.com  ")
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()
        XCTAssertEqual(config.edgeDomain, testEdgeDomain)
    }

    func testEdgeDomainRejectsScheme() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain("https://edge.example.com")
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()) { error in
            let e = error as? FlagInitError
            if case .invalidEdgeDomain(let message) = e {
                XCTAssertTrue(message.contains("scheme"))
            } else {
                XCTFail("Expected invalidEdgeDomain, got \(String(describing: error))")
            }
        }
    }

    func testEdgeDomainRejectsPath() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain("edge.example.com/flags")
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()) { error in
            let e = error as? FlagInitError
            if case .invalidEdgeDomain(let message) = e {
                XCTAssertTrue(message.contains("path"))
            } else {
                XCTFail("Expected invalidEdgeDomain, got \(String(describing: error))")
            }
        }
    }

    func testMissingEdgeDomain() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingEdgeDomain)
        }
    }

    func testBlankEdgeDomain() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain("   ")
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingEdgeDomain)
        }
    }

    func testMissingClientId() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingClientId)
        }
    }

    func testBlankClientId() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("   ")
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingClientId)
        }
    }

    func testMissingImsOrg() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingImsOrg)
        }
    }

    func testBlankImsOrg() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg("   ")
            .sandboxName(testSandbox)
            .clientId("client-a")
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingImsOrg)
        }
    }

    func testMissingSandboxName() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg(testImsOrg)
            .clientId("client-a")
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingSandboxName)
        }
    }

    func testBlankSandboxName() {
        XCTAssertThrowsError(try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg(testImsOrg)
            .sandboxName("   ")
            .clientId("client-a")
            .build()) { error in
            XCTAssertEqual(error as? FlagInitError, .missingSandboxName)
        }
    }

    func testGetters() throws {
        let config = try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg("my-org")
            .sandboxName("prod")
            .clientId("client-a")
            .build()
        XCTAssertEqual(config.edgeDomain, testEdgeDomain)
        XCTAssertEqual(config.imsOrg, "my-org")
        XCTAssertEqual(config.sandboxName, "prod")
        XCTAssertEqual(config.clientId, "client-a")
    }

    func testWhitespaceIsTrimmed() throws {
        let config = try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg("  my-org  ")
            .sandboxName("  prod  ")
            .clientId("  my-app  ")
            .build()
        XCTAssertEqual(config.imsOrg, "my-org")
        XCTAssertEqual(config.sandboxName, "prod")
        XCTAssertEqual(config.clientId, "my-app")
    }

    func testDescriptionDoesNotExposeSensitiveFields() throws {
        let config = try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg("secret-org")
            .sandboxName("secret-sandbox")
            .clientId("my-app")
            .build()
        let str = config.description
        XCTAssertFalse(str.contains("secret-org"))
        XCTAssertFalse(str.contains("secret-sandbox"))
    }

    func testUrlSessionDefaultsToNil() throws {
        let config = try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("app")
            .build()
        XCTAssertNil(config.urlSession)
    }

    func testUrlSessionReturnsSuppliedSession() throws {
        let custom = URLSession(configuration: .default)
        defer { custom.finishTasksAndInvalidate() }
        let config = try FlagConfiguration.builder()
            .edgeDomain(testEdgeDomain)
            .imsOrg(testImsOrg)
            .sandboxName(testSandbox)
            .clientId("app")
            .urlSession(custom)
            .build()
        XCTAssertTrue(config.urlSession === custom)
    }
}
