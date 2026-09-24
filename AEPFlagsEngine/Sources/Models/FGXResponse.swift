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

/// Parsed v2 combined CDN payload — feature groups, root `ttl`, and embedded context metadata.
/// Single source of truth for the CDN wire format. Internal — not part of the public API.
struct FGXResponse {

    let version: Int
    /// Raw CDN `ttl` from the response root.
    let ttl: Int?
    let contextVersion: String?
    let contextVariableMap: [String: String]
    let fieldDataTypeCache: [String: String]
    let featureGroups: [FeaturesResponse]

    /// Server-requested poll interval derived from root `ttl` (positive values only).
    var pollInterval: Int? {
        guard let ttl = ttl, ttl > 0 else { return nil }
        return ttl
    }

    /// Build a cache-facing metadata model from embedded context fields.
    func metadataResponse(etag: String?, isChanged: Bool) -> MetadataResponse {
        return MetadataResponse(contextVariableMap: contextVariableMap,
                                fieldDataTypeCache: fieldDataTypeCache,
                                etag: etag,
                                isChanged: isChanged,
                                contextVersion: contextVersion)
    }

    static let empty = FGXResponse(version: 0,
                                   ttl: nil,
                                   contextVersion: nil,
                                   contextVariableMap: [:],
                                   fieldDataTypeCache: [:],
                                   featureGroups: [])
}
