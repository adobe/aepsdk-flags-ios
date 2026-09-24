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

/// Thread-safe cache for reusable filter patches referenced by the `PATCH` operator.
/// Implemented as a singleton.
final class FilterPatchesCache {

    /// Shared instance.
    static let shared = FilterPatchesCache()

    private var patches: [String: IFilter] = [:]
    private var _lastModifiedMillis: Int64 = 0

    private let queue = DispatchQueue(label: "com.adobe.marketing.flags.filterpatches",
                                      attributes: .concurrent)

    private init() {}

    /// Returns the patch for `key`, or an `EmptyFilter` placeholder if absent.
    /// Returns a new `EmptyFilter` on miss
    /// rather than throwing.
    func patch(for key: String) -> IFilter {
        return queue.sync {
            if let cached = patches[key] { return cached }
            FlagLog.error("Could not find patch in cache for key: \(key)")
            return EmptyFilter()
        }
    }

    func hasPatch(for key: String) -> Bool {
        return queue.sync { patches[key] != nil }
    }

    func add(_ filter: IFilter, for key: String) {
        queue.sync(flags: .barrier) {
            self.patches[key] = filter
            self._lastModifiedMillis = Self.currentMillis()
        }
    }

    func remove(_ key: String) {
        queue.sync(flags: .barrier) {
            self.patches.removeValue(forKey: key)
            self._lastModifiedMillis = Self.currentMillis()
        }
    }

    /// Drop every cached patch. Clears every cached patch.
    func refresh() {
        queue.sync(flags: .barrier) {
            self.patches.removeAll(keepingCapacity: false)
            self._lastModifiedMillis = Self.currentMillis()
        }
    }

    var lastModifiedMillis: Int64 {
        queue.sync { _lastModifiedMillis }
    }

    var size: Int {
        queue.sync { patches.count }
    }

    @inline(__always)
    private static func currentMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
