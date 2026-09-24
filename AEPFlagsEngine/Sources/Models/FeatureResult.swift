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

/// Immutable representation of an evaluated feature flag. Thread-safe.
/// Returned by `Flag` evaluation methods.
/// For a feature-level **control** cohort sentinel, `id` is `CONTROL_GROUP_FEATURE_ID` and `key` is `nil`.
@objc(AEPMobileFeatureResult)
public final class FeatureResult: NSObject {

    @objc public let id: Int
    /// Feature flag key; `nil` for the policy control sentinel row.
    @objc public let key: String?
    @objc public let featureGroupKey: String?
    public let value: Any?
    /// Opaque metadata decoded from the wire `meta` Base64 string.
    @objc public let meta: String?
    @objc public let analyticsParam: AnalyticsParam?

    public init(id: Int,
                key: String?,
                featureGroupKey: String?,
                value: Any?,
                meta: String?,
                analyticsParam: AnalyticsParam? = nil) {
        self.id = id
        self.key = key
        self.featureGroupKey = featureGroupKey
        self.value = value
        self.meta = meta
        self.analyticsParam = analyticsParam
        super.init()
    }

    @objc(value)
    public var objcValue: Any? { value }
}
