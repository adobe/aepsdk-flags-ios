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

enum FlagResponseMapper {
    static func toFeatureEvaluationResult(_ featureMap: [String: Any]?) throws -> FeatureEvaluationResult? {
        guard let featureMap, !featureMap.isEmpty else {
            return nil
        }

        let id = try readRequiredInt(featureMap, key: FlagConstants.EventDataKeys.id)
        let key = try readRequiredString(featureMap, key: FlagConstants.EventDataKeys.key)
        let featureGroupKey = readOptionalString(featureMap[FlagConstants.EventDataKeys.featureGroupKey])
        let meta = readOptionalString(featureMap[FlagConstants.EventDataKeys.meta])
        let analyticsParam = try toAnalyticsParam(featureMap[FlagConstants.EventDataKeys.analyticsParam])

        return FeatureEvaluationResult(
            id: id,
            key: key,
            featureGroupKey: featureGroupKey,
            meta: meta,
            analyticsParam: analyticsParam
        )
    }

    static func toAnalyticsParam(_ analyticsObj: Any?) throws -> AnalyticsParam? {
        guard let analyticsMap = analyticsObj as? [String: Any], !analyticsMap.isEmpty else {
            return nil
        }

        let featureGroupId = try readRequiredInt(analyticsMap, key: FlagConstants.EventDataKeys.featureGroupId)
        let featureId = try readRequiredInt(analyticsMap, key: FlagConstants.EventDataKeys.featureId)
        let variantId = readOptionalString(analyticsMap[FlagConstants.EventDataKeys.variantId])

        return AnalyticsParam(featureGroupId: featureGroupId, featureId: featureId, variantId: variantId)
    }

    private static func readRequiredInt(_ source: [String: Any], key: String) throws -> Int {
        guard source.keys.contains(key) else {
            throw NSError(domain: "FlagResponseMapper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required numeric field: \(key)"])
        }
        return try coerceToInt(source[key], fieldName: key)
    }

    private static func coerceToInt(_ value: Any?, fieldName: String) throws -> Int {
        guard let value else {
            throw NSError(domain: "FlagResponseMapper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required numeric field: \(fieldName)"])
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let intValue = Int(trimmed) else {
                throw NSError(domain: "FlagResponseMapper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid numeric field: \(fieldName)"])
            }
            return intValue
        }
        throw NSError(domain: "FlagResponseMapper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid numeric field: \(fieldName)"])
    }

    private static func readRequiredString(_ source: [String: Any], key: String) throws -> String {
        guard source.keys.contains(key) else {
            throw NSError(domain: "FlagResponseMapper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required string field: \(key)"])
        }
        guard let string = coerceToString(source[key]) else {
            throw NSError(domain: "FlagResponseMapper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required string field: \(key)"])
        }
        return string
    }

    private static func readOptionalString(_ value: Any?) -> String? {
        guard let string = coerceToString(value), !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func coerceToString(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let bool = value as? Bool {
            return String(bool)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}
