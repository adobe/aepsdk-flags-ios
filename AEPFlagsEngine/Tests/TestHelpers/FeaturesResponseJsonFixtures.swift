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

/// Builds v2 combined CDN response JSON for parser and integration tests.
enum FeaturesResponseJsonFixtures {

    static let defaultContextVersion = "test-context-v1"

    static let defaultContexts = "[{\"id\":\"country\",\"type\":\"STRING\"}]"

    static var emptyResponse: String {
        bodyWithTtlOnly(120)
    }

    /// Minimal v2 body for HTTP-layer tests.
    static func minimalBody() -> String {
        return bodyWithSingleFeature("my-feature")
    }

    /// Full v2 CDN body with root `ttl`, `contextVersion`, `contexts`, and a `featureGroups` array payload.
    static func bodyWithFeatureGroups(_ groupsArrayContent: String) -> String {
        return bodyWithFeatureGroups(120, groupsArrayContent)
    }

    /// Full v2 CDN body with the given root `ttl` and `featureGroups` array payload.
    static func bodyWithFeatureGroups(_ ttl: Int,
                                      _ groupsArrayContent: String,
                                      contextVersion: String = defaultContextVersion,
                                      contexts: String = defaultContexts) -> String {
        return "{"
            + "\"v\":2,"
            + "\"ttl\":\(ttl),"
            + "\"contextVersion\":\"\(contextVersion)\","
            + "\"contexts\":\(contexts),"
            + "\"featureGroups\":[\(groupsArrayContent)]"
            + "}"
    }

    /// v2 CDN body with `ttl`, contexts, and an empty `featureGroups` array.
    static func bodyWithTtlOnly() -> String {
        return bodyWithTtlOnly(120)
    }

    /// v2 CDN body with the given root `ttl` and an empty `featureGroups` array.
    static func bodyWithTtlOnly(_ ttl: Int,
                                contextVersion: String = defaultContextVersion,
                                contexts: String = defaultContexts) -> String {
        return bodyWithFeatureGroups(ttl, "", contextVersion: contextVersion, contexts: contexts)
    }

    /// Single object inside the `featureGroups` array.
    static func featureGroup(_ groupId: Int, _ groupKey: String, _ fields: String) -> String {
        let trimmed = fields.hasPrefix(",") ? String(fields.dropFirst()) : fields
        return "{"
            + "\"id\":\(groupId),"
            + "\"key\":\"\(groupKey)\","
            + trimmed
            + "}"
    }

    /// Minimal feature object for combined CDN fixtures.
    static func featureObject(id: Int,
                              key: String,
                              criteriaJson: String? = nil,
                              metaBase64: String? = nil) -> String {
        var json = "{"
            + "\"id\":\(id),"
            + "\"key\":\"\(key)\","
            + "\"cohortingType\":\"ECID\","
            + "\"analyticsEnabled\":true"
        if let criteriaJson = criteriaJson {
            json += ",\"criteria\":\(criteriaJson)"
        }
        if let metaBase64 = metaBase64 {
            json += ",\"meta\":\"\(metaBase64)\""
        }
        json += "}"
        return json
    }

    /// Feature group containing a single named feature.
    static func singleFeatureGroup(_ featureKey: String,
                                   groupId: Int = 1001,
                                   groupKey: String = "default_feature_group",
                                   featureId: Int = 1001,
                                   criteriaJson: String? = nil) -> String {
        return featureGroup(groupId, groupKey,
                            "\"features\":[\(featureObject(id: featureId, key: featureKey, criteriaJson: criteriaJson))]")
    }

    /// Combined CDN body with one feature group and one feature.
    static func bodyWithSingleFeature(_ featureKey: String,
                                      ttl: Int = 120,
                                      contextVersion: String = defaultContextVersion,
                                      contexts: String = defaultContexts,
                                      criteriaJson: String? = nil) -> String {
        return bodyWithFeatureGroups(ttl,
                                   singleFeatureGroup(featureKey, criteriaJson: criteriaJson),
                                   contextVersion: contextVersion,
                                   contexts: contexts)
    }

    /// Features-only delta body: `contextVersion` and `featureGroups` without `contexts`.
    static func bodyFeaturesOnly(_ ttl: Int,
                                   _ contextVersion: String,
                                   _ groupsArrayContent: String) -> String {
        return "{"
            + "\"v\":2,"
            + "\"ttl\":\(ttl),"
            + "\"contextVersion\":\"\(contextVersion)\","
            + "\"featureGroups\":[\(groupsArrayContent)]"
            + "}"
    }

    /// Feature group with extra featureGroup-level fields before `features`.
    static func featureGroupWithFields(_ groupId: Int,
                                       _ groupKey: String,
                                       _ extraFields: String,
                                       _ featureObjects: String) -> String {
        let trimmed = extraFields.hasPrefix(",") ? String(extraFields.dropFirst()) : extraFields
        let fieldsPrefix = trimmed.isEmpty ? "" : trimmed + ","
        return "{"
            + "\"id\":\(groupId),"
            + "\"key\":\"\(groupKey)\","
            + fieldsPrefix
            + "\"features\":[\(featureObjects)]"
            + "}"
    }

    /// Minimal feature JSON fixture with optional trailing fields.
    static func feature(_ id: Int, _ key: String, _ extraFields: String) -> String {
        let trimmed = extraFields.hasPrefix(",") ? String(extraFields.dropFirst()) : extraFields
        var json = "{"
            + "\"id\":\(id),"
            + "\"key\":\"\(key)\""
        if !trimmed.isEmpty {
            json += ",\(trimmed)"
        }
        json += "}"
        return json
    }

    /// Minimal FGX response body fixture.
    static func minimalFGXBody() -> String {
        let featureJson = feature(1001, "my-feature", "\"cohortingType\":\"ECID\",\"analyticsEnabled\":true")
        return bodyWithFeatureGroups(
            120,
            featureGroup(1001, "default_feature_group", "\"features\":[\(featureJson)]"),
            contextVersion: "test-context-v1",
            contexts: "[{\"id\":\"country\",\"type\":\"STRING\"}]")
    }
}
