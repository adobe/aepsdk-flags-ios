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

/// A feature flag with its configuration and targeting criteria.
/// Mutable model with property accessors.
/// `hash` is renamed to `featureHash` to avoid colliding with `NSObject.hash`.
@objc(AEPMobileFeature)
public final class Feature: NSObject {

    @objc public var id: Int = 0
    @objc public var feature: String?
    @objc public var criteria: String?
    public var policyId: Int?
    var policy: PolicyCache.PolicyDetail?
    @objc(featureHash) public var featureHash: String?
    @objc public var enabled: Bool = false
    /// Wire `analyticsEnabled`; CDN payloads currently always send `true`.
    @objc public var analyticsEnabled: Bool = true
    public var value: Any?
    public var params: [String: Any]?
    /// Opaque metadata decoded from the wire `meta` Base64 string.
    @objc public var meta: String?

    private var cachedCohortingNamespace: String?
    private var cachedCohortingNamespaceResolved = false

    @objc public override init() {
        super.init()
    }

    /// Deep-copy initializer.
    public init(copying other: Feature) {
        self.id = other.id
        self.feature = other.feature
        self.criteria = other.criteria
        self.policyId = other.policyId
        self.policy = other.policy
        self.featureHash = other.featureHash
        self.enabled = other.enabled
        self.analyticsEnabled = other.analyticsEnabled
        self.value = other.value
        self.params = other.params
        self.meta = other.meta
        super.init()
    }

    /// Convenience alias for `feature`. Alias for the feature name.
    @objc public var name: String? { feature }

    /// Identity-map namespace for feature-level A/B bucketing, resolved from `params`.
    var cohortingNamespace: String? {
        if !cachedCohortingNamespaceResolved {
            cachedCohortingNamespace = PolicyEvaluator.resolveCohortingNamespace(params: params)
            cachedCohortingNamespaceResolved = true
        }
        return cachedCohortingNamespace
    }
}
