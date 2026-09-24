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

/// Service that compiles a criteria-JSON string into an `IFilter` and evaluates
/// it against `UserAttributes`.
/// Includes a per-`logicalId` filter compilation cache to avoid re-parsing
/// large criteria JSON blobs on every evaluation.
final class FilterService {

    private let filterTreeGenerator: FilterTreeGenerator
    private let criteriaFilterCache = CriteriaFilterCache()

    init(fieldDataTypeCache: [String: String]) {
        self.filterTreeGenerator = FilterTreeGenerator(fieldDataTypeCache: fieldDataTypeCache)
    }

    // MARK: - Evaluation

    /// `true` if `userAttributes` matches `filter`. `nil` filter matches vacuously.
    @discardableResult
    func isValid(_ userAttributes: UserAttributes, filter: IFilter?) -> Bool {
        return filter?.isValid(userAttributes) ?? true
    }

    /// Compile + evaluate `criteriaJson` on every call (no caching).
    /// Top-level parse failures fail closed (return `false`) for criteria that is present.
    func matches(criteriaJson: String?, userAttributes: UserAttributes) -> Bool {
        guard let json = criteriaJson, !json.isEmpty else { return true }
        return generateFilterTreeForEvaluation(json).isValid(userAttributes)
    }

    /// Compile criteria once per `(logicalId, criteriaVersion)`, then evaluate only the tree.
    /// `criteriaVersion` is normally the server criteria hash; when nil/empty, the full
    /// criteria string is used as the version key.
    func evaluateCriteriaCached(userAttributes: UserAttributes,
                                logicalId: String?,
                                criteriaJson: String?,
                                criteriaVersion: String?) -> Bool {
        guard let json = criteriaJson, !json.isEmpty else { return true }

        if let logicalId = logicalId, !logicalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let filter = criteriaFilterCache.getOrCreate(logicalId: logicalId,
                                                        criteriaJson: json,
                                                        criteriaVersion: criteriaVersion,
                                                        owner: self)
            return isValid(userAttributes, filter: filter)
        }
        return generateFilterTreeForEvaluation(json).isValid(userAttributes)
    }

    /// Build a filter tree for the evaluation path (fail-closed on top-level parse errors).
    func generateFilterTreeForEvaluation(_ criteriaJson: String) -> IFilter {
        return filterTreeGenerator.filterTree(criteriaJson,
                                              isRootTagPresent: true,
                                              rejectOnParseError: true)
    }

    /// Build a filter from a Swift map / JSON string. Used by `ContainsAndFilterDelegator`.
    func filter(fromMap value: Any?) -> IFilter {
        guard let value = value else { return EmptyFilter() }

        if let map = value as? [String: Any] {
            return filterTreeGenerator.parseTree(map, rejectOnParseError: false)
        }
        if let string = value as? String {
            return filterTreeGenerator.filterTree(string, isRootTagPresent: false)
        }
        if let filter = value as? IFilter {
            return filter
        }
        return EmptyFilter()
    }

    // MARK: - Cache

    /// Per-`logicalId` cached compilation. Multiple compiles for different ids may
    /// run concurrently — the cache itself uses a serial barrier queue for writes
    /// and concurrent reads.
    private final class CriteriaFilterCache {

        private var slots: [String: CachedSlot] = [:]
        private let queue = DispatchQueue(label: "com.adobe.marketing.flags.criteriacache",
                                          attributes: .concurrent)

        func getOrCreate(logicalId: String,
                         criteriaJson: String,
                         criteriaVersion: String?,
                         owner: FilterService) -> IFilter {
            let versionKey = (criteriaVersion?.isEmpty == false) ? criteriaVersion! : criteriaJson

            // Fast path — concurrent read.
            if let cached = queue.sync(execute: { slots[logicalId] }),
               cached.versionKey == versionKey {
                return cached.filter
            }

            // Slow path — barrier so only one writer per id at a time.
            return queue.sync(flags: .barrier) {
                if let existing = slots[logicalId], existing.versionKey == versionKey {
                    return existing.filter
                }
                let filter = owner.generateFilterTreeForEvaluation(criteriaJson)
                slots[logicalId] = CachedSlot(versionKey: versionKey, filter: filter)
                return filter
            }
        }

        private struct CachedSlot {
            let versionKey: String
            let filter: IFilter
        }
    }
}
