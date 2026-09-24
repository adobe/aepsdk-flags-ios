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

/// Verifies metadata cache updates are gated by `contextVersion`, independent of featureGroups.
final class FGXResponseMetadataCacheTests: XCTestCase {

    private func metadata(version: String) -> MetadataResponse {
        MetadataResponse(contextVariableMap: ["COUNTRY": "country"],
                         fieldDataTypeCache: ["country": "STRING"],
                         etag: "\"e1\"",
                         isChanged: true,
                         contextVersion: version)
    }

    func testPutMetadataSkipsWhenContextVersionUnchanged() {
        let cache = SDKClientCache()
        XCTAssertTrue(cache.putMetadata(metadata(version: "ctx-v1")))
        XCTAssertEqual(cache.getMetadata()?.contextVersion, "ctx-v1")

        XCTAssertFalse(cache.putMetadata(metadata(version: "ctx-v1")))
        XCTAssertEqual(cache.getMetadata()?.contextVersion, "ctx-v1")
    }

    func testPutMetadataUpdatesWhenContextVersionChanges() {
        let cache = SDKClientCache()
        XCTAssertTrue(cache.putMetadata(metadata(version: "ctx-v1")))

        let updated = MetadataResponse(contextVariableMap: ["LOCALE": "locale"],
                                       fieldDataTypeCache: ["locale": "STRING"],
                                       etag: "\"e2\"",
                                       isChanged: true,
                                       contextVersion: "ctx-v2")
        XCTAssertTrue(cache.putMetadata(updated))
        XCTAssertEqual(cache.getMetadata()?.contextVersion, "ctx-v2")
        XCTAssertEqual(cache.getMetadata()?.fieldDataTypeCache["locale"], "STRING")
    }

    func testFGXResponseMetadataBridge() {
        let fgx = FGXResponse(version: 2,
                              ttl: 120,
                              contextVersion: "ctx-bridge",
                              contextVariableMap: ["PLATFORM": "PLATFORM"],
                              fieldDataTypeCache: ["PLATFORM": "STRING"],
                              featureGroups: [])
        let metadata = fgx.metadataResponse(etag: "\"e3\"", isChanged: true)
        XCTAssertEqual(metadata.contextVersion, "ctx-bridge")
        XCTAssertEqual(metadata.fieldDataTypeCache["PLATFORM"], "STRING")
        XCTAssertEqual(metadata.etag, "\"e3\"")
        XCTAssertTrue(metadata.isChanged)
    }

    func testPutMetadataReturnsFalseForEmptyContextVersion() {
        let cache = SDKClientCache()
        let response = MetadataResponse(contextVariableMap: [:],
                                          fieldDataTypeCache: ["country": "STRING"],
                                          etag: "\"e1\"",
                                          isChanged: true,
                                          contextVersion: "")
        XCTAssertFalse(cache.putMetadata(response))
        XCTAssertFalse(cache.hasMetadata())
    }

    func testPutMetadataReturnsFalseWhenNotChanged() {
        let cache = SDKClientCache()
        let response = MetadataResponse(contextVariableMap: [:],
                                          fieldDataTypeCache: ["country": "STRING"],
                                          etag: "\"e1\"",
                                          isChanged: false,
                                          contextVersion: "ctx-v1")
        XCTAssertFalse(cache.putMetadata(response))
        XCTAssertFalse(cache.hasMetadata())
    }
}
