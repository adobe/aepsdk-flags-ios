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

class FlagConstantsTests: XCTestCase {
    func testExtensionName() {
        XCTAssertEqual("com.adobe.flags", FlagConstants.extensionName)
    }

    func testExtensionVersion() {
        // Version is single-sourced here and bumped by the update-version workflow; assert it is a
        // well-formed semantic version rather than a fixed literal so a bump does not break tests.
        let version = FlagConstants.extensionVersion
        XCTAssertFalse(version.isEmpty)
        XCTAssertNotNil(
            version.range(of: #"^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$"#, options: .regularExpression),
            "extensionVersion '\(version)' is not a valid semantic version"
        )
    }

    func testFriendlyName() {
        XCTAssertEqual("Flags", FlagConstants.friendlyName)
    }

    func testLogTag() {
        XCTAssertEqual("Flags", FlagConstants.logTag)
    }

    func testEventType() {
        XCTAssertEqual("com.adobe.eventType.flags", FlagConstants.EventType.flags)
    }

    func testEventSources() {
        XCTAssertEqual("com.adobe.eventSource.requestContent", FlagConstants.EventSource.requestContent)
        XCTAssertEqual("com.adobe.eventSource.responseContent", FlagConstants.EventSource.responseContent)
        XCTAssertEqual("com.adobe.eventSource.requestReset", FlagConstants.EventSource.requestReset)
    }

    func testRequestTypes() {
        XCTAssertEqual("getfeature", FlagConstants.EventDataValues.requestTypeGetFeature)
        XCTAssertEqual("isfeatureenabled", FlagConstants.EventDataValues.requestTypeIsEnabled)
    }

    func testConfigurationKeys() {
        XCTAssertFalse(FlagConstants.Configuration.edgeDomain.isEmpty)
        XCTAssertFalse(FlagConstants.Configuration.defaultEdgeDomain.isEmpty)
        XCTAssertFalse(FlagConstants.Configuration.flagsClientId.isEmpty)
        XCTAssertFalse(FlagConstants.Configuration.flagsSandbox.isEmpty)
        XCTAssertFalse(FlagConstants.Configuration.experienceCloudOrg.isEmpty)
    }

    func testEdgeIdentity_extensionName() {
        XCTAssertEqual("com.adobe.edge.identity", FlagConstants.EdgeIdentity.extensionName)
    }

    func testEventDataKeys_featureGroupStrings() {
        XCTAssertEqual("featureGroupKey", FlagConstants.EventDataKeys.featureGroupKey)
        XCTAssertEqual("featureGroupId", FlagConstants.EventDataKeys.featureGroupId)
    }

    func testEdge_requestKeys_matchAEPEdgeEventDataKeys() {
        XCTAssertEqual("request", FlagConstants.Edge.Request.key)
        XCTAssertEqual("path", FlagConstants.Edge.Request.path)
    }

    func testEdge_collectPath_matchesDataCollectionApi() {
        XCTAssertEqual("/v1/collect", FlagConstants.Edge.Request.collectPath)
    }

    func testEdge_propositionDisplayEventType() {
        XCTAssertEqual("decisioning.propositionDisplay", FlagConstants.Edge.eventTypePropositionDisplay)
    }

    func testExposureQueue_defaults() {
        XCTAssertEqual(20, FlagConstants.ExposureQueue.batchSize)
        XCTAssertEqual(150_000, FlagConstants.ExposureQueue.flushIntervalMs)
    }
}
