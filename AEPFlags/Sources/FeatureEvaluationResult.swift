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

/// Immutable feature payload returned by ``Flag/getFeature(featureKey:evaluationContext:completion:)``.
@objc(AEPFeatureEvaluationResult)
public final class FeatureEvaluationResult: NSObject {
    private let idValue: Int
    private let keyValue: String
    private let featureGroupKeyValue: String?
    private let metaValue: String?
    private let analyticsParamValue: AnalyticsParam?

    @objc public init(
        id: Int,
        key: String,
        featureGroupKey: String?,
        meta: String?,
        analyticsParam: AnalyticsParam?
    ) {
        idValue = id
        keyValue = key
        featureGroupKeyValue = featureGroupKey
        metaValue = meta
        analyticsParamValue = analyticsParam
        super.init()
    }

    @objc public var id: Int {
        idValue
    }

    @objc public var key: String {
        keyValue
    }

    @objc public var featureGroupKey: String? {
        featureGroupKeyValue
    }

    @objc public var meta: String? {
        metaValue
    }

    @objc public var analyticsParam: AnalyticsParam? {
        analyticsParamValue
    }
}
