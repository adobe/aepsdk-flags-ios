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

/// Maps engine feature results for extension API responses.
enum FeatureResultMapper {
    /// A feature is enabled when it exists and has a non-empty key.
    static func isEnabledFeatureResult(_ feature: FlagsSDKFeatureResult?) -> Bool {
        guard let feature, let key = feature.key, !key.isEmpty else {
            return false
        }
        return true
    }

    static func featureResultToMap(_ feature: FlagsSDKFeatureResult) -> [String: Any] {
        var map: [String: Any] = [
            FlagConstants.EventDataKeys.id: feature.id,
            FlagConstants.EventDataKeys.key: feature.key ?? NSNull()
        ]

        if let featureGroupKey = feature.featureGroupKey {
            map[FlagConstants.EventDataKeys.featureGroupKey] = featureGroupKey
        }

        if let meta = feature.meta?.trimmingCharacters(in: .whitespacesAndNewlines), !meta.isEmpty {
            map[FlagConstants.EventDataKeys.meta] = meta
        }

        if let analytics = feature.analyticsParam {
            var analyticsMap: [String: Any] = [
                FlagConstants.EventDataKeys.featureGroupId: analytics.featureGroupId,
                FlagConstants.EventDataKeys.featureId: analytics.featureId
            ]
            if let variantId = analytics.variantId {
                analyticsMap[FlagConstants.EventDataKeys.variantId] = variantId
            }
            map[FlagConstants.EventDataKeys.analyticsParam] = analyticsMap
        }

        return map
    }
}
