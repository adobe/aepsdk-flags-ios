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

/// Immutable analytics parameters for a single evaluated feature.
/// Thread-safe.
@objc(AEPMobileAnalyticsParam)
public final class AnalyticsParam: NSObject {

    /// Numeric feature group identifier.
    @objc public let featureGroupId: Int
    /// Numeric feature identifier.
    @objc public let featureId: Int
    /// Feature key (name).
    @objc public let featureKey: String?
    /// Variant identifier from policy bucketing, or `nil` if no policy was evaluated.
    @objc public let variantId: String?

    @objc public init(featureGroupId: Int,
                      featureId: Int,
                      featureKey: String?,
                      variantId: String?) {
        self.featureGroupId = featureGroupId
        self.featureId = featureId
        self.featureKey = featureKey
        self.variantId = variantId
        super.init()
    }
}
