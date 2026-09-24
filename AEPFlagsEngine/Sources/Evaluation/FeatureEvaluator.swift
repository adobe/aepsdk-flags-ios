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

/// Evaluates feature flags against cached featureGroup data, targeting criteria, and A/B policies.
final class FeatureEvaluator {

    private static let controlGroupFeatureId = FlagConstants.Policy.CONTROL_GROUP_FEATURE_ID

    private let clientId: String
    private let cache: SDKClientCache
    private let policyCache: PolicyCache
    private var _filterService: FilterService?
    private let filterServiceQueue = DispatchQueue(
        label: "com.adobe.marketing.flags.evaluator",
        attributes: .concurrent)

    /// Thread-safe accessor for `filterService`.
    /// Reads execute concurrently; writes use a barrier to serialize against reads.
    private var filterService: FilterService? {
        filterServiceQueue.sync { _filterService }
    }

    init(clientId: String, cache: SDKClientCache, policyCache: PolicyCache) {
        self.clientId = clientId
        self.cache = cache
        self.policyCache = policyCache
    }

    func setFilterService(_ service: FilterService) {
        filterServiceQueue.sync(flags: .barrier) { self._filterService = service }
    }

    func clearFilterService() {
        filterServiceQueue.sync(flags: .barrier) { self._filterService = nil }
    }

    func evaluateAll(request: GetFeatureRequest) -> [FeatureResult] {
        guard let cacheEntry = cache.getFeatures(clientId: clientId), !cacheEntry.isEmpty else {
            return []
        }

        let userAttributes = UserAttributes.from(context: request.context)
        let identityMap = request.identityMap

        var resolvedFeatureGroups: [Int: FeatureGroupResolution] = [:]
        var results: [FeatureResult] = []

        for (featureKey, indexed) in cacheEntry.allEntries {
            let featureGroup = indexed.featureGroup
            let resolution: FeatureGroupResolution
            if let existing = resolvedFeatureGroups[featureGroup.featureGroupId] {
                resolution = existing
            } else {
                let computed = resolveFeatureGroupContextOrExcluded(featureGroup: featureGroup,
                                                               userAttributes: userAttributes,
                                                               identityMap: identityMap)
                resolvedFeatureGroups[featureGroup.featureGroupId] = computed
                resolution = computed
            }

            if case .excluded = resolution { continue }

            guard case .included(let ctx) = resolution else { continue }

            if let feature = indexed.feature {
                if let result = evaluateSingleFeature(feature: feature,
                                                      featureGroupId: ctx.featureGroupId,
                                                      featureGroupKey: ctx.featureGroupKey,
                                                      featureGroupVariantId: ctx.featureGroupVariantId,
                                                      userAttributes: userAttributes,
                                                      identityMap: identityMap,
                                                      cohortingNamespace: indexed.cohortingNamespace) {
                    results.append(result)
                }
            } else {
                let analytics = AnalyticsParam(featureGroupId: ctx.featureGroupId,
                                               featureId: 0,
                                               featureKey: featureKey,
                                               variantId: ctx.featureGroupVariantId)
                results.append(FeatureResult(id: 0,
                                            key: featureKey,
                                            featureGroupKey: ctx.featureGroupKey,
                                            value: nil,
                                            meta: nil,
                                            analyticsParam: analytics))
            }
        }
        return results
    }

    func evaluate(featureName: String?, request: GetFeatureRequest) -> FeatureResult? {
        guard let featureName = featureName else { return nil }
        guard let cacheEntry = cache.getFeatures(clientId: clientId) else { return nil }
        guard let indexed = cacheEntry.findFeature(featureName) else { return nil }

        let userAttributes = UserAttributes.from(context: request.context)
        let identityMap = request.identityMap

        guard let ctx = resolveFeatureGroupContext(featureGroup: indexed.featureGroup,
                                              userAttributes: userAttributes,
                                              identityMap: identityMap) else { return nil }

        if let feature = indexed.feature {
            return evaluateSingleFeature(feature: feature,
                                        featureGroupId: ctx.featureGroupId,
                                        featureGroupKey: ctx.featureGroupKey,
                                        featureGroupVariantId: ctx.featureGroupVariantId,
                                        userAttributes: userAttributes,
                                        identityMap: identityMap,
                                        cohortingNamespace: indexed.cohortingNamespace)
        }

        let analytics = AnalyticsParam(featureGroupId: ctx.featureGroupId,
                                       featureId: 0,
                                       featureKey: featureName,
                                       variantId: ctx.featureGroupVariantId)
        return FeatureResult(id: 0,
                            key: featureName,
                            featureGroupKey: ctx.featureGroupKey,
                            value: nil,
                            meta: nil,
                            analyticsParam: analytics)
    }

    func isEnabled(featureName: String?, request: GetFeatureRequest) -> Bool {
        guard let result = evaluate(featureName: featureName, request: request) else { return false }
        return result.key != nil
    }

    // MARK: - Feature group / feature resolution

    private enum FeatureGroupResolution {
        case excluded
        case included(FeatureGroupContext)
    }

    private struct FeatureGroupContext {
        let featureGroupId: Int
        let featureGroupKey: String?
        let featureGroupVariantId: String?
    }

    private func resolveFeatureGroupContextOrExcluded(featureGroup: SDKClientCache.FeatureGroupRef,
                                               userAttributes: UserAttributes,
                                               identityMap: [String: [[String: Any]]]) -> FeatureGroupResolution {
        if let ctx = resolveFeatureGroupContext(featureGroup: featureGroup,
                                          userAttributes: userAttributes,
                                          identityMap: identityMap) {
            return .included(ctx)
        }
        return .excluded
    }

    private func resolveFeatureGroupContext(featureGroup: SDKClientCache.FeatureGroupRef,
                                       userAttributes: UserAttributes,
                                       identityMap: [String: [[String: Any]]]) -> FeatureGroupContext? {
        if !matchesFeatureGroupCriteria(featureGroup: featureGroup, userAttributes: userAttributes) {
            return nil
        }

        let featureGroupVariant = resolvePolicy(policyId: featureGroup.policyId,
                                           identityMap: identityMap,
                                           cohortingNamespace: featureGroup.cohortingNamespace)
        if let featureGroupVariant = featureGroupVariant, featureGroupVariant.controlGroup {
            return nil
        }

        let featureGroupVariantId = featureGroupVariant?.variantId
        return FeatureGroupContext(featureGroupId: featureGroup.featureGroupId,
                             featureGroupKey: featureGroup.featureGroupName,
                             featureGroupVariantId: featureGroupVariantId)
    }

    private func evaluateSingleFeature(feature: Feature,
                                       featureGroupId: Int,
                                       featureGroupKey: String?,
                                       featureGroupVariantId: String?,
                                       userAttributes: UserAttributes,
                                       identityMap: [String: [[String: Any]]],
                                       cohortingNamespace: String?) -> FeatureResult? {
        if !matchesFeatureCriteria(feature: feature, featureGroupId: featureGroupId, userAttributes: userAttributes) {
            return nil
        }

        var variantId = featureGroupVariantId
        let featureVariant = resolvePolicy(policyId: feature.policyId,
                                           identityMap: identityMap,
                                           cohortingNamespace: cohortingNamespace)

        if let featureVariant = featureVariant {
            variantId = featureVariant.variantId
            if featureVariant.controlGroup {
                let analytics = AnalyticsParam(featureGroupId: featureGroupId,
                                               featureId: feature.id,
                                               featureKey: feature.feature,
                                               variantId: variantId)
                return FeatureResult(id: Self.controlGroupFeatureId,
                                    key: nil,
                                    featureGroupKey: nil,
                                    value: nil,
                                    meta: nil,
                                    analyticsParam: analytics)
            }
        }

        let analytics = AnalyticsParam(featureGroupId: featureGroupId,
                                       featureId: feature.id,
                                       featureKey: feature.feature,
                                       variantId: variantId)
        return FeatureResult(id: feature.id,
                            key: feature.feature,
                            featureGroupKey: featureGroupKey,
                            value: feature.value,
                            meta: feature.meta,
                            analyticsParam: analytics)
    }

    private func matchesFeatureGroupCriteria(featureGroup: SDKClientCache.FeatureGroupRef,
                                        userAttributes: UserAttributes) -> Bool {
        guard let criteria = featureGroup.criteria, !criteria.isEmpty else { return true }
        guard let filterService = filterService else {
            FlagLog.warning("[Flags] Criteria present but filter service is not initialized for client: \(clientId)")
            return false
        }
        let logicalId = "featureGroup:\(featureGroup.featureGroupId)"
        return filterService.evaluateCriteriaCached(userAttributes: userAttributes,
                                                    logicalId: logicalId,
                                                    criteriaJson: criteria,
                                                    criteriaVersion: featureGroup.criteriaHash)
    }

    private func matchesFeatureCriteria(feature: Feature,
                                        featureGroupId: Int,
                                        userAttributes: UserAttributes) -> Bool {
        guard let criteria = feature.criteria, !criteria.isEmpty else { return true }
        guard let filterService = filterService else {
            FlagLog.warning("[Flags] Criteria present but filter service is not initialized for client: \(clientId)")
            return false
        }
        let logicalId = "feature:\(featureGroupId):\(feature.id)"
        return filterService.evaluateCriteriaCached(userAttributes: userAttributes,
                                                    logicalId: logicalId,
                                                    criteriaJson: criteria,
                                                    criteriaVersion: feature.featureHash)
    }

    private func resolvePolicy(policyId: Int?,
                               identityMap: [String: [[String: Any]]],
                               cohortingNamespace: String?) -> PolicyEvaluator.PolicyVariantResponse? {
        guard let policyId = policyId else { return nil }
        let identifier = PolicyEvaluator.getIdentifier(identityMap: identityMap,
                                                       cohortingNamespace: cohortingNamespace)
        return PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache,
                                                        policyId: policyId,
                                                        identifier: identifier)
    }
}
