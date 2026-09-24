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

#if canImport(ObjectiveC)
import ObjectiveC
#endif
import XCTest
@testable import FlagsEngine

final class FlagTests: XCTestCase {

    private let clientId = "thread-test"
    private var flag: Flag!

    override func setUp() {
        super.setUp()
        let cfg = try! FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("test-org")
            .sandboxName("test-sandbox")
            .clientId(clientId)
            .build()
        flag = Flag(configuration: cfg)
        flag.testMarkInitializedWithoutNetwork()
    }

    override func tearDown() {
        flag?.close()
        flag = nil
        super.tearDown()
    }

func testObjectiveCClassName() throws {
#if canImport(ObjectiveC)
    XCTAssertEqual(String(cString: class_getName(Flag.self)), "AEPMobileFlagEngine")
#else
    throw XCTSkip("Objective-C runtime not available on this platform.")
#endif
}

    private func putFeatureGroups(_ featureGroups: FeaturesResponse...) {
        flag.testClientCacheForUnitTests.putFeatures(clientId: clientId, features: Array(featureGroups), etag: "etag-1")
    }

    private func featureGroupNamed(_ name: String, _ features: Feature...) -> FeaturesResponse {
        let r = FeaturesResponse()
        r.featureGroupName = name
        r.featuresObj = Array(features)
        return r
    }

    private func featureGroupStrings(_ name: String, _ names: String...) -> FeaturesResponse {
        let r = FeaturesResponse()
        r.featureGroupName = name
        r.features = Array(names)
        return r
    }

    private func featureNamed(_ n: String) -> Feature {
        let f = Feature()
        f.feature = n
        return f
    }

    private func featureValue(_ n: String, _ v: Any) -> Feature {
        let f = Feature()
        f.feature = n
        f.value = v
        return f
    }

    private func sortedKeys(_ results: [FeatureResult]) -> [String] {
        results.compactMap { $0.key }.sorted()
    }

    func testNotInitializedThrowsOnFeatureCall() throws {
        let cfg = try FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("org")
            .sandboxName("prod")
            .clientId("app")
            .build()
        let bare = Flag(configuration: cfg)
        XCTAssertThrowsError(try bare.getFeatures(for: nil)) { err in
            XCTAssertTrue(err is FlagClientError)
        }
    }

    func testGetFeaturesReturnsAllFromCache() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("alpha"), featureNamed("beta")))
        let keys = sortedKeys(try flag.getFeatures(for: nil))
        XCTAssertEqual(keys, ["alpha", "beta"])
    }

    func testGetFeaturesEmptyWhenNoCache() throws {
        XCTAssertEqual(try flag.getFeatures(for: nil).count, 0)
    }

    func testGetFeaturesNullRequestUsesDefaults() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("feat-a")))
        XCTAssertEqual(try flag.getFeatures(for: nil).count, 1)
    }

    func testGetFeaturesWithContextRequest() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("feat-a")))
        let req = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        XCTAssertEqual(try flag.getFeatures(for: req).count, 1)
    }

    func testGetFeaturesMultipleFeatureGroups() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("feat-a")),
                    featureGroupNamed("R2", featureNamed("feat-b"), featureNamed("feat-c")))
        let keys = Set(try flag.getFeatures(for: nil).compactMap { $0.key })
        XCTAssertEqual(keys, ["feat-a", "feat-b", "feat-c"])
    }

    func testGetFeaturesThrowsWhenNotInitialized() throws {
        flag.testMarkUninitialized()
        XCTAssertThrowsError(try flag.getFeatures(for: nil)) { err in
            XCTAssertTrue(err is FlagClientError)
        }
    }

    func testGetFeaturesThrowsAfterClose() throws {
        flag.close()
        XCTAssertThrowsError(try flag.getFeatures(for: nil))
    }

    func testGetFeatureReturnsMatch() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("dark-mode"), featureValue("banner-text", "Welcome!")))
        let r = try flag.getFeature(named: "dark-mode", for: nil)
        XCTAssertEqual(r?.key, "dark-mode")
        XCTAssertEqual(r?.featureGroupKey, "R1")
    }

    func testGetFeatureReturnsValue() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("dark-mode"), featureValue("banner-text", "Welcome!")))
        let r = try flag.getFeature(named: "banner-text", for: nil)
        XCTAssertEqual(r?.value as? String, "Welcome!")
    }

    func testGetFeatureUnknownReturnsNil() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("dark-mode")))
        XCTAssertNil(try flag.getFeature(named: "nonexistent", for: nil))
    }

    func testGetFeatureEmptyNameReturnsNil() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("dark-mode")))
        XCTAssertNil(try flag.getFeature(named: "", for: nil))
    }

    func testGetFeatureThrowsWhenNotInitialized() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("dark-mode")))
        flag.testMarkUninitialized()
        XCTAssertThrowsError(try flag.getFeature(named: "dark-mode", for: nil)) { err in
            XCTAssertTrue(err is FlagClientError)
        }
    }

    func testGetFeatureWithContextRequest() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("dark-mode")))
        let req = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        XCTAssertNotNil(try flag.getFeature(named: "dark-mode", for: req))
    }

    func testGetFeatureAfterCloseThrows() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("dark-mode")))
        flag.close()
        XCTAssertThrowsError(try flag.getFeature(named: "dark-mode", for: nil))
    }

    func testIsFeatureEnabledBasics() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("enabled-flag"), featureNamed("another-flag")))
        XCTAssertTrue(try flag.isFeatureEnabled("enabled-flag", for: nil))
        XCTAssertTrue(try flag.isFeatureEnabled("another-flag", for: nil))
        XCTAssertFalse(try flag.isFeatureEnabled("nonexistent", for: nil))
    }

    func testIsFeatureEnabledWithContextRequest() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("enabled-flag")))
        let req = GetFeatureRequest.builder().context(["country": ["US"]]).build()
        XCTAssertTrue(try flag.isFeatureEnabled("enabled-flag", for: req))
    }

    func testIsFeatureEnabledNullNameFalse() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("enabled-flag")))
        XCTAssertFalse(try flag.isFeatureEnabled("", for: nil))
    }

    func testIsFeatureEnabledThrowsWhenNotInitialized() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("enabled-flag")))
        flag.testMarkUninitialized()
        XCTAssertThrowsError(try flag.isFeatureEnabled("enabled-flag", for: nil))
    }

    func testIsFeatureEnabledThrowsAfterClose() throws {
        putFeatureGroups(featureGroupNamed("R1", featureNamed("enabled-flag")))
        flag.close()
        XCTAssertThrowsError(try flag.isFeatureEnabled("enabled-flag", for: nil))
    }

    func testLifecycleIsInitialized() {
        XCTAssertTrue(flag.isInitialized)
    }

    func testLifecycleNotInitializedAfterClose() {
        flag.close()
        XCTAssertFalse(flag.isInitialized)
    }

    func testCloseIdempotent() {
        flag.close()
        flag.close()
        XCTAssertFalse(flag.isInitialized)
    }

    func testClientIdGetter() {
        XCTAssertEqual(flag.clientId, clientId)
    }

    func testSdkConfiguration() {
        XCTAssertEqual(flag.sdkConfiguration.clientId, clientId)
    }

    // MARK: - HTTP session wiring

    func testApiProxyUsesSharedUrlSessionWhenConfigurationProvidesOne() throws {
        let shared = URLSession(configuration: .ephemeral)
        let cfg = try FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("o")
            .sandboxName("s")
            .clientId("c")
            .urlSession(shared)
            .build()
        let client = Flag(configuration: cfg)
        XCTAssertFalse(client.apiProxy.ownsSession)
        XCTAssertTrue(client.apiProxy.urlSession === shared)
    }

    func testApiProxyCreatesOwnedSessionWhenConfigurationOmitsUrlSession() throws {
        let cfg = try FlagConfiguration.builder()
            .edgeDomain("edge.example.com")
            .imsOrg("o")
            .sandboxName("s")
            .clientId("c")
            .build()
        let client = Flag(configuration: cfg)
        XCTAssertTrue(client.apiProxy.ownsSession)
    }

    // MARK: - setAppState

    func testSetAppStateThrowsWhenNotInitialized() {
        flag.testMarkUninitialized()
        XCTAssertThrowsError(try flag.setAppState(.background)) { err in
            XCTAssertTrue(err is FlagClientError)
        }
    }

    func testSetAppStateThrowsAfterClose() {
        flag.close()
        XCTAssertThrowsError(try flag.setAppState(.foreground)) { err in
            XCTAssertTrue(err is FlagClientError)
        }
    }

    func testSetAppStateBackgroundDoesNotThrow() {
        XCTAssertNoThrow(try flag.setAppState(.background))
    }

    func testSetAppStateForegroundDoesNotThrow() {
        XCTAssertNoThrow(try flag.setAppState(.foreground))
    }

    func testSetAppStateRepeatedBackgroundIsIdempotent() {
        XCTAssertNoThrow(try flag.setAppState(.background))
        XCTAssertNoThrow(try flag.setAppState(.background))
    }

    func testSetAppStateRepeatedForegroundIsIdempotent() {
        XCTAssertNoThrow(try flag.setAppState(.background))
        XCTAssertNoThrow(try flag.setAppState(.foreground))
        XCTAssertNoThrow(try flag.setAppState(.foreground))
    }
}
