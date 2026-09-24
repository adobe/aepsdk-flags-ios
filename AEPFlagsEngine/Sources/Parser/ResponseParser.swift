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

/// Parses raw JSON responses from the Edge CDN into SDK model objects.
/// Internal — not part of the public API.
enum ResponseParser {

    private static let keyId = "id"
    private static let keyType = "type"
    private static let keyPolicy = "policy"
    private static let keySeed = "seed"
    private static let keyVariantId = "variantId"
    private static let keyStart = "start"
    private static let keyEnd = "end"
    private static let keyPercentage = "percentage"
    private static let keyPreviewUserVariantMap = "previewUserVariantMap"

    // MARK: - Public entry points

    /// Parse a v2 combined CDN response body into an `FGXResponse`.
    /// - Throws: ``ResponseParseException`` when the body is not valid combined-response JSON.
    static func parseFGXResponse(_ body: String?) throws -> FGXResponse {
        do {
            guard let body = body, let data = body.data(using: .utf8) else {
                throw ResponseParseException("Failed to parse Edge response")
            }
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw ResponseParseException("Failed to parse Edge response")
            }

            let version = (json[FlagConstants.JSONKeys.VERSION] as? NSNumber)?.intValue ?? 0
            let ttl = (json[FlagConstants.JSONKeys.TTL] as? NSNumber)?.intValue
            let contextVersion = json[FlagConstants.JSONKeys.CONTEXT_VERSION] as? String

            var contextVariableMap: [String: String] = [:]
            var fieldDataTypeCache: [String: String] = [:]
            if let contexts = json[FlagConstants.JSONKeys.CONTEXTS] as? [Any] {
                parseContextsArray(contexts,
                                   contextVariableMap: &contextVariableMap,
                                   fieldDataTypeCache: &fieldDataTypeCache)
            }

            guard let groups = json[FlagConstants.JSONKeys.FEATURE_GROUPS] as? [Any] else {
                return FGXResponse(version: version,
                                   ttl: ttl,
                                   contextVersion: contextVersion,
                                   contextVariableMap: contextVariableMap,
                                   fieldDataTypeCache: fieldDataTypeCache,
                                   featureGroups: [])
            }

            var result: [FeaturesResponse] = []
            result.reserveCapacity(groups.count)
            for element in groups {
                guard let groupJson = element as? [String: Any] else { continue }
                result.append(parseFeatureGroup(groupJson))
            }
            return FGXResponse(version: version,
                               ttl: ttl,
                               contextVersion: contextVersion,
                               contextVariableMap: contextVariableMap,
                               fieldDataTypeCache: fieldDataTypeCache,
                               featureGroups: result)
        } catch let error as ResponseParseException {
            throw error
        } catch {
            FlagLog.error("Failed to parse Edge response: \(error.localizedDescription)")
            throw ResponseParseException("Failed to parse Edge response", underlying: error)
        }
    }

    // MARK: - Feature groups

    private static func parseFeatureGroup(_ groupJson: [String: Any]) -> FeaturesResponse {
        let response = FeaturesResponse()

        if let groupId = (groupJson[keyId] as? NSNumber)?.intValue {
            response.featureGroupId = groupId
        }
        if let groupKey = groupJson[FlagConstants.JSONKeys.KEY] as? String {
            response.featureGroupName = groupKey
        }
        response.params = parseCohortingParams(groupJson)
        if let criteria = groupJson[FlagConstants.JSONKeys.CRITERIA] {
            response.criteria = extractCriteria(criteria)
        }
        if let policyId = (groupJson[FlagConstants.JSONKeys.POLICY_ID] as? NSNumber)?.intValue {
            response.policyId = policyId
        }
        if let policyJson = groupJson[keyPolicy] as? [String: Any] {
            response.policy = parsePolicyDetail(policyJson)
        }
        if let hash = groupJson[FlagConstants.JSONKeys.HASH] {
            response.hash = extractNullableString(hash)
        }
        if let featuresArray = groupJson[FlagConstants.JSONKeys.FEATURES] as? [Any] {
            parseFeaturesArray(featuresArray, into: response)
        }
        return response
    }

    private static func parseFeature(_ featureJson: [String: Any]) -> Feature {
        let feature = Feature()

        if let id = (featureJson[keyId] as? NSNumber)?.intValue { feature.id = id }
        if let name = featureJson[FlagConstants.JSONKeys.KEY] as? String { feature.feature = name }
        feature.params = parseCohortingParams(featureJson)
        if let criteria = featureJson[FlagConstants.JSONKeys.CRITERIA] {
            feature.criteria = extractCriteria(criteria)
        }
        if let policyId = (featureJson[FlagConstants.JSONKeys.POLICY_ID] as? NSNumber)?.intValue {
            feature.policyId = policyId
        }
        if let policyJson = featureJson[keyPolicy] as? [String: Any] {
            feature.policy = parsePolicyDetail(policyJson)
        }
        if let hash = featureJson[FlagConstants.JSONKeys.HASH] {
            feature.featureHash = extractNullableString(hash)
        }
        if let meta = featureJson[FlagConstants.JSONKeys.META] {
            feature.meta = parseMeta(meta)
        }
        if let analyticsEnabled = featureJson[FlagConstants.JSONKeys.ANALYTICS_ENABLED] as? Bool {
            feature.analyticsEnabled = analyticsEnabled
        } else if let analyticsEnabled = featureJson[FlagConstants.JSONKeys.ANALYTICS_ENABLED] as? NSNumber {
            feature.analyticsEnabled = analyticsEnabled.boolValue
        }
        return feature
    }

    private static func parsePolicyDetail(_ policyJson: [String: Any]) -> PolicyCache.PolicyDetail? {
        do {
            return try parsePolicyDetailOrThrow(policyJson)
        } catch {
            FlagLog.warning("Failed to parse policy detail: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parsePolicyDetailOrThrow(_ policyJson: [String: Any]) throws -> PolicyCache.PolicyDetail {
        let id = (policyJson[keyId] as? NSNumber)?.intValue
        let hashAlgorithmType = policyJson[FlagConstants.JSONKeys.HASH_ALGORITHM] as? String
        let seed = policyJson[keySeed] as? String

        var buckets: [PolicyCache.PolicyBucket] = []
        if let bucketsArray = policyJson[FlagConstants.JSONKeys.BUCKETS] as? [Any] {
            buckets.reserveCapacity(bucketsArray.count)
            for element in bucketsArray {
                guard let b = element as? [String: Any] else {
                    throw ResponseParseException("Invalid policy bucket")
                }
                let variantId = bucketVariantId(from: b)
                let start = try intValue(from: b[keyStart], defaultValue: 0, field: "start")
                let end = try intValue(from: b[keyEnd], defaultValue: 0, field: "end")
                let percentage = try intValue(from: b[keyPercentage], defaultValue: 0, field: "percentage")
                buckets.append(PolicyCache.PolicyBucket(variantId: variantId,
                                                       startRange: start,
                                                       endRange: end,
                                                       percentage: percentage))
            }
        }

        var preview: [String: String]?
        if let previewMap = policyJson[keyPreviewUserVariantMap] as? [String: Any] {
            var collected: [String: String] = [:]
            for (key, value) in previewMap {
                if let stringValue = value as? String {
                    collected[key] = stringValue
                }
            }
            preview = collected
        }

        return PolicyCache.PolicyDetail(id: id,
                                        hashAlgorithmType: hashAlgorithmType,
                                        seed: seed,
                                        buckets: buckets,
                                        previewUserVariantMap: preview)
    }

    private static func intValue(from value: Any?, defaultValue: Int, field: String) throws -> Int {
        if value == nil { return defaultValue }
        if let number = value as? NSNumber { return number.intValue }
        throw ResponseParseException("Invalid policy \(field)")
    }

    private static func parseFeaturesArray(_ array: [Any], into response: FeaturesResponse) {
        var featureNames: [String] = []
        var featuresObj: [Feature] = []
        featureNames.reserveCapacity(array.count)
        featuresObj.reserveCapacity(array.count)

        for element in array {
            guard let object = element as? [String: Any] else { continue }
            let feature = parseFeature(object)
            featuresObj.append(feature)
            if let name = feature.feature { featureNames.append(name) }
        }
        response.features = featureNames
        if !featuresObj.isEmpty { response.featuresObj = featuresObj }
    }

    // MARK: - Contexts

    /// Each context entry is `{ "id": "<name>", "type": "<wireType>" }`.
    /// `type` is normalized to uppercase; `COMPLEX` maps to `STRING`.
    private static func parseContextsArray(_ array: [Any],
                                           contextVariableMap: inout [String: String],
                                           fieldDataTypeCache: inout [String: String]) {
        for element in array {
            guard let attr = element as? [String: Any],
                  let name = attr[keyId] as? String,
                  let typeRaw = attr[keyType] as? String else { continue }

            var dataType = typeRaw.uppercased()
            if dataType == "COMPLEX" { dataType = "STRING" }
            contextVariableMap[name.uppercased()] = name
            fieldDataTypeCache[name] = dataType
        }
    }

    // MARK: - Helpers

    /// `variantId` may be a JSON string, number (e.g. `0`), or null/omitted.
    private static func bucketVariantId(from bucket: [String: Any]) -> String {
        guard let raw = bucket[keyVariantId], !(raw is NSNull) else { return "" }
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        return ""
    }

    /// Criteria arrives as a JSON object or escaped JSON string (re-serialized for downstream parsing).
    private static func extractCriteria(_ element: Any?) -> String? {
        guard let element = element, !(element is NSNull) else { return nil }
        if let s = element as? String { return s }
        if let data = try? JSONSerialization.data(withJSONObject: element, options: []),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return nil
    }

    /// `meta` is a Base64-encoded opaque string on the wire; decoded text is returned as-is.
    private static func parseMeta(_ element: Any?) -> String? {
        guard let element = element, !(element is NSNull) else { return nil }
        guard let encoded = element as? String, !encoded.isEmpty else { return nil }

        let decodedData: Data?
        if let data = Data(base64Encoded: encoded) {
            decodedData = data
        } else if let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) {
            decodedData = data
        } else {
            FlagLog.warning("[Flags] Failed to Base64-decode feature meta")
            return nil
        }

        guard let data = decodedData,
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty else {
            FlagLog.warning("[Flags] Failed to decode feature meta as UTF-8 string")
            return nil
        }
        return decoded
    }

    private static func extractNullableString(_ element: Any?) -> String? {
        guard let element = element, !(element is NSNull) else { return nil }
        if let s = element as? String { return s }
        if let n = element as? NSNumber { return n.stringValue }
        return nil
    }

    private static func parseCohortingParams(_ json: [String: Any]) -> [String: Any]? {
        var params: [String: Any] = [:]
        if let nested = json[FlagConstants.JSONKeys.PARAMS] as? [String: Any] {
            mergeCohortingFields(into: &params, from: nested)
        }
        mergeCohortingFields(into: &params, from: json)
        return params.isEmpty ? nil : params
    }

    private static func mergeCohortingFields(into target: inout [String: Any], from source: [String: Any]) {
        mergeStringField(into: &target, from: source, key: FlagConstants.JSONKeys.COHORTING_TYPE)
        mergeStringField(into: &target, from: source, key: FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE)
    }

    private static func mergeStringField(into target: inout [String: Any],
                                         from source: [String: Any],
                                         key: String) {
        guard let value = source[key] as? String, !value.isEmpty else { return }
        target[key] = value
    }
}
