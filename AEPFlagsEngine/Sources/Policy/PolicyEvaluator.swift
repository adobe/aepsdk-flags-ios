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

/// Evaluates A/B policy assignments for consistent user bucketing.
enum PolicyEvaluator {

    private static let defaultHashStrategy = MurmurHashStrategy()
    private static let controlGroup = PolicyVariantResponse(variantId: FlagConstants.Policy.CONTROL_GROUP_VARIANT_ID,
                                                            controlGroup: true)

    /// Session-stable fallback identifier when no stable bucketing identifier is available.
    private static let sessionFallbackId: String = UUID().uuidString

    /// Policy variant response from policy evaluation.
    struct PolicyVariantResponse {
        let variantId: String
        let controlGroup: Bool
    }

    /// Simple percentage-based split (distinct from `PolicyCache.PolicyBucket` hash ranges).
    struct PercentageSplit {
        let variantId: Int
        let percentage: Int
    }

    /// Resolves the bucketing identifier from an identity map entry for the given namespace.
    static func getIdentifier(identityMap: [String: [[String: Any]]]?,
                              cohortingNamespace: String?) -> String {
        if let cohortingNamespace = cohortingNamespace?.trimmingCharacters(in: .whitespacesAndNewlines),
           Utils.hasLength(cohortingNamespace),
           let identityMap = identityMap,
           !identityMap.isEmpty,
           let entries = identityMap[cohortingNamespace],
           !entries.isEmpty {
            var selected: [String: Any]?
            for entry in entries {
                if isPrimaryIdentityEntry(entry) {
                    selected = entry
                    break
                }
            }
            if selected == nil {
                selected = entries.first
            }
            if let selected = selected,
               let id = selected[FlagConstants.IdentityMap.ENTRY_KEY_ID] as? String,
               Utils.hasLength(id) {
                return id
            }
        }
        return sessionFallbackId
    }

    /// Resolve variant using cached policy detail, or fall back to 50/50 when policy is missing.
    static func getPolicyVariantFromCache(policyCache: PolicyCache?,
                                          policyId: Int?,
                                          identifier: String?) -> PolicyVariantResponse {
        guard let policyCache = policyCache, let policyId = policyId, let identifier = identifier else {
            return controlGroup
        }

        if let detail = policyCache.policy(for: policyId) {
            return getPolicyVariant(policyDetail: detail, identifier: identifier)
        }
        return getPolicyVariant(policyId: policyId, identifier: identifier, controlPercentage: 50)
    }

    /// Evaluate buckets from a `PolicyDetail`.
    static func getPolicyVariant(policyDetail: PolicyCache.PolicyDetail?, identifier: String?) -> PolicyVariantResponse {
        guard let policyDetail = policyDetail, let identifier = identifier else {
            return controlGroup
        }

        let hashAlgorithmType = policyDetail.hashAlgorithmType
        if hashAlgorithmType == HashFactory.AlgorithmType.previewSimpleHash.rawValue {
            if let previewMap = policyDetail.previewUserVariantMap,
               let variantId = previewMap[identifier] {
                let isControl = isControlVariantId(variantId)
                return PolicyVariantResponse(variantId: isControl ? FlagConstants.Policy.CONTROL_GROUP_VARIANT_ID : variantId,
                                              controlGroup: isControl)
            }
            return controlGroup
        }

        let strategy = HashFactory.strategy(for: hashAlgorithmType)
        let hashValue = strategy.hash(identifier: identifier, seed: policyDetail.seed)

        for bucket in policyDetail.buckets where bucket.contains(hashValue) {
            let variantId = bucket.variantId
            let isControl = isControlVariantId(variantId)
            return PolicyVariantResponse(variantId: isControl ? FlagConstants.Policy.CONTROL_GROUP_VARIANT_ID : variantId,
                                          controlGroup: isControl)
        }
        return controlGroup
    }

    /// Ad-hoc evaluation with explicit percentage splits.
    static func getPolicyVariant(policyId: Int,
                                 identifier: String,
                                 buckets: [PercentageSplit]) -> PolicyVariantResponse {
        guard !buckets.isEmpty else { return controlGroup }

        let seed = String(policyId)
        let hashValue = defaultHashStrategy.hash(identifier: identifier, seed: seed)
        let bucket = hashValue / defaultHashStrategy.multiplier

        var cumulative = 0
        for split in buckets {
            cumulative += split.percentage
            if bucket < cumulative {
                let isControl = (split.variantId == 0)
                return PolicyVariantResponse(variantId: String(split.variantId), controlGroup: isControl)
            }
        }
        return controlGroup
    }

    /// Fallback when policy detail is not cached — `controlPercentage` is control bucket size 0...100.
    static func getPolicyVariant(policyId: Int,
                                 identifier: String,
                                 controlPercentage: Int) -> PolicyVariantResponse {
        let seed = String(policyId)
        let hashValue = defaultHashStrategy.hash(identifier: identifier, seed: seed)
        let bucket = hashValue / defaultHashStrategy.multiplier
        let isControl = bucket < controlPercentage
        let variantId = isControl ? FlagConstants.Policy.CONTROL_GROUP_VARIANT_ID : "1"
        return PolicyVariantResponse(variantId: variantId, controlGroup: isControl)
    }

    /// Resolves the identity-map namespace for policy bucketing from feature or feature group params.
    static func resolveCohortingNamespace(params: [String: Any]?) -> String? {
        guard let params = params else { return nil }
        guard let typeValue = params[FlagConstants.JSONKeys.COHORTING_TYPE] as? String else {
            return nil
        }
        let cohortingType = typeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Utils.hasLength(cohortingType) else { return nil }

        if cohortingType == CohortingType.ecid.rawString {
            return FlagConstants.Policy.DEFAULT_COHORTING_NAMESPACE
        }
        if cohortingType == CohortingType.sticky.rawString {
            if let namespaceCode = params[FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE] as? String {
                let trimmed = namespaceCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if Utils.hasLength(trimmed) {
                    return trimmed
                }
            }
            return nil
        }
        return nil
    }

    private static func isPrimaryIdentityEntry(_ entry: [String: Any]) -> Bool {
        switch entry[FlagConstants.IdentityMap.ENTRY_KEY_PRIMARY] {
        case let primary as Bool:
            return primary
        case let primary as NSNumber:
            return primary.boolValue
        default:
            return false
        }
    }

    private static func isControlVariantId(_ variantId: String?) -> Bool {
        guard let variantId = variantId, !variantId.isEmpty else { return true }
        return variantId == FlagConstants.Policy.CONTROL_GROUP_VARIANT_ID
    }
}
