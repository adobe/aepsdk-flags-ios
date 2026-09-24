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

/// Thread-safe in-memory cache for feature flags and metadata.
final class SDKClientCache {

    /// Feature-group-level fields needed during evaluation.
    struct FeatureGroupRef: Hashable {
        let featureGroupId: Int
        let featureGroupName: String?
        let criteria: String?
        let criteriaHash: String?
        let policyId: Int?
        let cohortingNamespace: String?

        init(_ featureGroup: FeaturesResponse) {
            self.featureGroupId = featureGroup.featureGroupId
            self.featureGroupName = featureGroup.featureGroupName
            self.criteria = featureGroup.criteria
            self.criteriaHash = featureGroup.hash
            self.policyId = featureGroup.policyId
            self.cohortingNamespace = featureGroup.cohortingNamespace
        }
    }

    /// Pre-indexed feature within its owning featureGroup.
    struct IndexedFeature {
        let featureGroup: FeatureGroupRef
        let feature: Feature?
        let cohortingNamespace: String?

        init(featureGroup: FeatureGroupRef, feature: Feature?) {
            self.featureGroup = featureGroup
            self.feature = feature
            if let feature = feature {
                self.cohortingNamespace = feature.cohortingNamespace
            } else {
                self.cohortingNamespace = featureGroup.cohortingNamespace
            }
        }
    }

    /// Immutable cache snapshot indexed by feature name.
    /// Insertion order is preserved so bulk evaluation returns features in server response order.
    final class CacheEntry {

        private let featureIndex: [String: IndexedFeature]
        private let orderedKeys: [String]
        let etag: String?
        let timestampMillis: Int64

        init(featureGroups: [FeaturesResponse], etag: String?) {
            self.etag = etag
            self.timestampMillis = Int64(Date().timeIntervalSince1970 * 1000)
            let built = Self.buildIndex(featureGroups: featureGroups)
            self.featureIndex = built.index
            self.orderedKeys = built.orderedKeys
        }

        func findFeature(_ featureName: String) -> IndexedFeature? {
            return featureIndex[featureName]
        }

        var allEntries: [(key: String, value: IndexedFeature)] {
            return orderedKeys.compactMap { key in
                guard let value = featureIndex[key] else { return nil }
                return (key, value)
            }
        }

        var isEmpty: Bool { featureIndex.isEmpty }

        private static func buildIndex(featureGroups: [FeaturesResponse])
            -> (index: [String: IndexedFeature], orderedKeys: [String]) {
            guard !featureGroups.isEmpty else { return ([:], []) }
            var index: [String: IndexedFeature] = [:]
            var orderedKeys: [String] = []
            for featureGroup in featureGroups {
                let ref = FeatureGroupRef(featureGroup)
                if let objs = featureGroup.featuresObj, !objs.isEmpty {
                    for f in objs {
                        if let name = f.feature {
                            if index[name] == nil { orderedKeys.append(name) }
                            index[name] = IndexedFeature(featureGroup: ref, feature: f)
                        }
                    }
                } else if let names = featureGroup.features {
                    for name in names {
                        if index[name] == nil { orderedKeys.append(name) }
                        index[name] = IndexedFeature(featureGroup: ref, feature: nil)
                    }
                }
            }
            return (index, orderedKeys)
        }
    }

    struct MetadataCacheEntry {
        let contextVariableMap: [String: String]
        let fieldDataTypeCache: [String: String]
        let contextVersion: String?
        let etag: String?
        let timestampMillis: Int64

        init(contextVariableMap: [String: String],
             fieldDataTypeCache: [String: String],
             contextVersion: String?,
             etag: String?) {
            self.contextVariableMap = contextVariableMap
            self.fieldDataTypeCache = fieldDataTypeCache
            self.contextVersion = contextVersion
            self.etag = etag
            self.timestampMillis = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }

    private var featureCache: [String: CacheEntry] = [:]
    private var metadataCache: MetadataCacheEntry?

    private let queue = DispatchQueue(label: "com.adobe.marketing.flags.sdkclientcache",
                                      attributes: .concurrent)

    init() {}

    func putFeatures(clientId: String, features: [FeaturesResponse]?, etag: String?) {
        guard !clientId.isEmpty, let features = features else { return }
        queue.sync(flags: .barrier) {
            self.featureCache[clientId] = CacheEntry(featureGroups: features, etag: etag)
        }
    }

    func getFeatures(clientId: String) -> CacheEntry? {
        return queue.sync { featureCache[clientId] }
    }

    func getFeaturesEtag(clientId: String) -> String? {
        return queue.sync { featureCache[clientId]?.etag }
    }

    func hasFeatures(clientId: String) -> Bool {
        return queue.sync { featureCache[clientId] != nil }
    }

    func removeFeatures(clientId: String) {
        _ = queue.sync(flags: .barrier) {
            self.featureCache.removeValue(forKey: clientId)
        }
    }

    /// Updates metadata cache only when `contextVersion` differs from the cached value.
    /// Returns `true` when the cache entry was replaced.
    @discardableResult
    func putMetadata(_ response: MetadataResponse?) -> Bool {
        guard let response = response, response.isChanged else { return false }
        guard let newVersion = response.contextVersion, !newVersion.isEmpty else { return false }

        return queue.sync(flags: .barrier) {
            if self.metadataCache?.contextVersion == newVersion {
                return false
            }
            self.metadataCache = MetadataCacheEntry(
                contextVariableMap: response.contextVariableMap,
                fieldDataTypeCache: response.fieldDataTypeCache,
                contextVersion: newVersion,
                etag: response.etag
            )
            return true
        }
    }

    func getMetadata() -> MetadataCacheEntry? {
        return queue.sync { metadataCache }
    }

    func getMetadataEtag() -> String? {
        return queue.sync { metadataCache?.etag }
    }

    func hasMetadata() -> Bool {
        return queue.sync { metadataCache != nil }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            self.featureCache.removeAll(keepingCapacity: false)
            self.metadataCache = nil
        }
    }

    var size: Int {
        queue.sync { featureCache.count }
    }
}
