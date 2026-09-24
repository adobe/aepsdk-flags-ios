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

/// Context metadata extracted from the combined CDN features response.
/// Carries context variable metadata and field data-type mappings used by the rule engine.
final class MetadataResponse {

    /// Map of context variable names to their declared types.
    let contextVariableMap: [String: String]
    /// Map of field names to their data types (wire strings — parsed by `FieldDataType.from(_:)`).
    let fieldDataTypeCache: [String: String]
    /// HTTP ETag for cache validation, or `nil` if absent.
    let etag: String?
    /// `true` when metadata content should be applied (caller sets after `contextVersion` comparison).
    let isChanged: Bool
    /// Logical version of context definitions from the CDN body.
    let contextVersion: String?

    init(contextVariableMap: [String: String],
         fieldDataTypeCache: [String: String],
         etag: String?,
         isChanged: Bool,
         contextVersion: String? = nil) {
        self.contextVariableMap = contextVariableMap
        self.fieldDataTypeCache = fieldDataTypeCache
        self.etag = etag
        self.isChanged = isChanged
        self.contextVersion = contextVersion
    }
}
