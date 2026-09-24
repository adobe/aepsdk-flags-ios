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

/// Thread-safe cache for policy configurations.
/// Reads use the concurrent queue without a barrier;
/// writes use a barrier to serialize against concurrent reads.
final class PolicyCache {

    private var policies: [Int: PolicyDetail] = [:]
    private let queue = DispatchQueue(label: "com.adobe.marketing.flags.policycache",
                                      attributes: .concurrent)

    init() {}

    // MARK: - Lookup / mutation

    func policy(for id: Int) -> PolicyDetail? {
        return queue.sync { policies[id] }
    }

    func put(_ detail: PolicyDetail, for id: Int) {
        queue.sync(flags: .barrier) {
            self.policies[id] = detail
        }
    }

    func remove(_ id: Int) {
        queue.sync(flags: .barrier) {
            _ = self.policies.removeValue(forKey: id)
        }
    }

    func contains(_ id: Int) -> Bool {
        return queue.sync { policies[id] != nil }
    }

    func all() -> [Int: PolicyDetail] {
        return queue.sync { policies }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            self.policies.removeAll(keepingCapacity: false)
        }
    }

    var size: Int {
        queue.sync { policies.count }
    }

    // MARK: - Nested types

    /// Policy detail containing bucket configuration for A/B assignment.
    struct PolicyDetail {
        let id: Int?
        let hashAlgorithmType: String?
        let seed: String?
        let buckets: [PolicyBucket]
        let previewUserVariantMap: [String: String]?
        let cachedAtMillis: Int64

        init(id: Int?,
             hashAlgorithmType: String?,
             seed: String?,
             buckets: [PolicyBucket],
             previewUserVariantMap: [String: String]?) {
            self.id = id
            self.hashAlgorithmType = hashAlgorithmType
            self.seed = seed
            self.buckets = buckets
            self.previewUserVariantMap = previewUserVariantMap
            self.cachedAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }

    /// Policy bucket with inclusive hash range.
    struct PolicyBucket {
        let variantId: String
        let startRange: Int
        let endRange: Int
        let percentage: Int

        /// `true` if `value` falls within `startRange...endRange` (inclusive).
        @inline(__always)
        func contains(_ value: Int) -> Bool {
            return value >= startRange && value <= endRange
        }
    }
}
