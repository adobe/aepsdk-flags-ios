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

/// Thread-safe cache for rule-field data-type mappings, AEP metadata, and per-field
/// metadata maps.
/// Entries are added or updated via the `set*` methods for the lifetime of the
/// instance. Reads use the concurrent queue without a barrier; writes use a
/// barrier to serialize against concurrent reads.
final class FieldDataTypeCache {

    private var fieldDataTypeCache: [String: FieldDataType] = [:]
    private var aepMetadataCache: [String: FieldDataType] = [:]
    private var fieldMetadataCache: [String: [String: String]] = [:]
    private var _lastModifiedMillis: Int64 = 0

    private let queue = DispatchQueue(label: "com.adobe.marketing.flags.fielddatatype",
                                      attributes: .concurrent)

    init() {}

    // MARK: - Field data type

    @discardableResult
    func setFieldDataType(_ dataType: FieldDataType, for fieldName: String) -> FieldDataTypeCache {
        queue.sync(flags: .barrier) {
            self.fieldDataTypeCache[fieldName] = dataType
            self._lastModifiedMillis = Self.currentMillis()
        }
        return self
    }

    /// Field data type for `fieldName`, or `nil` if not registered.
    func fieldDataType(for fieldName: String) -> FieldDataType? {
        return queue.sync { fieldDataTypeCache[fieldName] }
    }

    // MARK: - AEP metadata

    @discardableResult
    func setAepMetadata(_ dataType: FieldDataType, for fieldName: String) -> FieldDataTypeCache {
        queue.sync(flags: .barrier) {
            self.aepMetadataCache[fieldName] = dataType
            self._lastModifiedMillis = Self.currentMillis()
        }
        return self
    }

    func aepMetadata(for fieldName: String) -> FieldDataType? {
        return queue.sync { aepMetadataCache[fieldName] }
    }

    func hasAepMetadata(for fieldName: String) -> Bool {
        return queue.sync { aepMetadataCache[fieldName] != nil }
    }

    // MARK: - Per-field metadata maps

    @discardableResult
    func setFieldMetadata(_ metadata: [String: String], for fieldName: String) -> FieldDataTypeCache {
        queue.sync(flags: .barrier) {
            self.fieldMetadataCache[fieldName] = metadata
        }
        return self
    }

    func fieldMetadata(for fieldName: String) -> [String: String]? {
        return queue.sync { fieldMetadataCache[fieldName] }
    }

    // MARK: - Snapshot / sizes

    var lastModifiedMillis: Int64 {
        queue.sync { _lastModifiedMillis }
    }

    var size: Int {
        queue.sync { fieldDataTypeCache.count }
    }

    var aepMetadataSize: Int {
        queue.sync { aepMetadataCache.count }
    }

    /// Snapshot of `fieldDataTypeCache` mapped to wire strings (`FieldDataType.rawValue`).
    /// Returns a snapshot map.
    func toStringMap() -> [String: String] {
        return queue.sync {
            var out: [String: String] = [:]
            out.reserveCapacity(fieldDataTypeCache.count)
            for (key, value) in fieldDataTypeCache { out[key] = value.rawValue }
            return out
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private static func currentMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
