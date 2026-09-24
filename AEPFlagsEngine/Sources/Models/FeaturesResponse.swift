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

/// A feature group containing one or more feature flags.
/// Mutable model populated by `ResponseParser`.
final class FeaturesResponse {

    var featureGroupId: Int = 0
    var featureGroupName: String?
    var features: [String]?
    var featuresObj: [Feature]?
    var criteria: String?
    var policyId: Int?
    var policy: PolicyCache.PolicyDetail?
    var hash: String?
    var params: [String: Any]?

    private var cachedCohortingNamespace: String?
    private var cachedCohortingNamespaceResolved = false

    init() {}

    /// Deep-copy initializer.
    init(copying other: FeaturesResponse) {
        self.featureGroupId = other.featureGroupId
        self.featureGroupName = other.featureGroupName
        self.features = other.features
        self.featuresObj = other.featuresObj?.map(Feature.init(copying:))
        self.criteria = other.criteria
        self.policyId = other.policyId
        self.policy = other.policy
        self.hash = other.hash
        self.params = other.params
    }

    /// Identity-map namespace for feature-group-level A/B bucketing, resolved from `params`.
    var cohortingNamespace: String? {
        if !cachedCohortingNamespaceResolved {
            cachedCohortingNamespace = PolicyEvaluator.resolveCohortingNamespace(params: params)
            cachedCohortingNamespaceResolved = true
        }
        return cachedCohortingNamespace
    }
}
