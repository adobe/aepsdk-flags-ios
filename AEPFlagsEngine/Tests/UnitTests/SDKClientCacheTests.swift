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

/// Cache indexing tests (insertion order + empty feature names).
final class SDKClientCacheTests: XCTestCase {

    func testAllEntriesPreservesServerInsertionOrder() {
        let featureGroup = FeaturesResponse()
        featureGroup.featureGroupId = 1
        featureGroup.featureGroupName = "ordered-featureGroup"
        featureGroup.features = ["z-feature", "a-feature", "m-feature"]

        let entry = SDKClientCache.CacheEntry(featureGroups: [featureGroup], etag: "\"etag-1\"")
        let keys = entry.allEntries.map(\.key)

        XCTAssertEqual(keys, ["z-feature", "a-feature", "m-feature"])
    }

    func testAllEntriesPreservesOrderWhenKeyIsUpdated() {
        let first = FeaturesResponse()
        first.featureGroupId = 1
        first.featureGroupName = "featureGroup-a"
        first.features = ["shared", "only-a"]

        let second = FeaturesResponse()
        second.featureGroupId = 2
        second.featureGroupName = "featureGroup-b"
        second.features = ["shared", "only-b"]

        let entry = SDKClientCache.CacheEntry(featureGroups: [first, second], etag: "\"etag-2\"")
        let keys = entry.allEntries.map(\.key)

        XCTAssertEqual(keys, ["shared", "only-a", "only-b"])
        XCTAssertNotNil(entry.findFeature("shared"))
    }

    func testIndexesEmptyStringFeatureName() {
        let featureGroup = FeaturesResponse()
        featureGroup.featureGroupId = 1
        featureGroup.featureGroupName = "empty-name-featureGroup"
        featureGroup.features = [""]

        let entry = SDKClientCache.CacheEntry(featureGroups: [featureGroup], etag: "\"etag-3\"")
        XCTAssertNotNil(entry.findFeature(""))
        XCTAssertEqual(entry.allEntries.map(\.key), [""])
    }
}
