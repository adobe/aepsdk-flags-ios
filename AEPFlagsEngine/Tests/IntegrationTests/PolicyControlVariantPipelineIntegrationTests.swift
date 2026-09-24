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

import XCTest
@testable import FlagsEngine

final class PolicyControlVariantPipelineIntegrationTests: XCTestCase {

    private let clientId = "pipeline-client"

    private func cachePoliciesLikeSdkManager(_ policyCache: PolicyCache, featureGroups: [FeaturesResponse]) {
        for featureGroup in featureGroups {
            if let pid = featureGroup.policyId, let detail = featureGroup.policy {
                policyCache.put(detail, for: pid)
            }
            if let features = featureGroup.featuresObj {
                for f in features {
                    if let pid = f.policyId, let detail = f.policy {
                        policyCache.put(detail, for: pid)
                    }
                }
            }
        }
    }

    func testPreviewEmptyThroughParserCacheAndEvaluator() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(700, "PreviewRel",
                "\"features\":[{\"id\":42,\"key\":\"gate-a\",\"cohortingType\":\"ECID\",\"policyId\":10001,"
                    + "\"policy\":{"
                    + "\"hashAlgorithm\":\"PREVIEW_SIMPLE_HASH\",\"seed\":\"s\","
                    + "\"buckets\":[],"
                    + "\"previewUserVariantMap\":{"
                    + "\"v-preview-empty\":\"\","
                    + "\"v-preview-zero\":\"0\","
                    + "\"v-treat\":\"42\""
                    + "}"
                    + "}"
                    + "}]"))

        let fgx = try ResponseParser.parseFGXResponse(json)
        let featureGroups = fgx.featureGroups
        XCTAssertEqual(featureGroups.count, 1)
        XCTAssertEqual(featureGroups[0].featureGroupId, 700)
        XCTAssertEqual(featureGroups[0].featureGroupName, "PreviewRel")

        let cache = SDKClientCache()
        let policyCache = PolicyCache()
        cache.putFeatures(clientId: clientId, features: featureGroups, etag: "etag-pipeline-1")
        cachePoliciesLikeSdkManager(policyCache, featureGroups: featureGroups)

        let evaluator = FeatureEvaluator(clientId: clientId, cache: cache, policyCache: policyCache)

        let emptyPreview = evaluator.evaluateAll(request: IdentityMapTestHelpers.request(namespace: IdentityMapTestHelpers.defaultCohortingNamespace, id: "v-preview-empty"))
        XCTAssertEqual(emptyPreview.count, 1)
        XCTAssertEqual(emptyPreview[0].id, FlagConstants.Policy.CONTROL_GROUP_FEATURE_ID)
        XCTAssertNil(emptyPreview[0].key)
        XCTAssertNotNil(emptyPreview[0].analyticsParam)
        XCTAssertEqual(emptyPreview[0].analyticsParam?.variantId, "0")

        let zeroPreview = evaluator.evaluateAll(request: IdentityMapTestHelpers.request(namespace: IdentityMapTestHelpers.defaultCohortingNamespace, id: "v-preview-zero"))
        XCTAssertEqual(zeroPreview[0].analyticsParam?.variantId, "0")

        let treat = evaluator.evaluateAll(request: IdentityMapTestHelpers.request(namespace: IdentityMapTestHelpers.defaultCohortingNamespace, id: "v-treat"))
        XCTAssertEqual(treat.count, 1)
        XCTAssertEqual(treat[0].key, "gate-a")
        XCTAssertEqual(treat[0].analyticsParam?.variantId, "42")
        XCTAssertFalse(treat[0].id < 0)
    }

    func testMurmurOmittedVariantIdThroughParserCacheAndEvaluator() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(701, "MurmurRel",
                "\"features\":[{\"id\":7,\"key\":\"cohort-x\",\"cohortingType\":\"ECID\",\"policyId\":10002,"
                    + "\"policy\":{"
                    + "\"hashAlgorithm\":\"MURMUR_HASH\",\"seed\":\"seed-murmur-int\","
                    + "\"buckets\":["
                    + "{\"start\":0,\"end\":4999},"
                    + "{\"variantId\":\"9\",\"start\":5000,\"end\":9999}"
                    + "]"
                    + "}"
                    + "}]"))

        let fgx = try ResponseParser.parseFGXResponse(json)
        let featureGroups = fgx.featureGroups
        XCTAssertEqual(featureGroups.count, 1)
        XCTAssertEqual(featureGroups[0].featureGroupId, 701)

        let parsed = featureGroups[0].featuresObj![0].policy!
        XCTAssertEqual(parsed.buckets[0].variantId, "")
        XCTAssertEqual(parsed.buckets[1].variantId, "9")

        let cache = SDKClientCache()
        let policyCache = PolicyCache()
        cache.putFeatures(clientId: clientId, features: featureGroups, etag: "etag-pipeline-2")
        cachePoliciesLikeSdkManager(policyCache, featureGroups: featureGroups)

        let evaluator = FeatureEvaluator(clientId: clientId, cache: cache, policyCache: policyCache)

        var controlIdentifier: String?
        for i in 0..<250_000 {
            let id = "murmur-probe_\(i)"
            let r = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 10002, identifier: id)
            if r.controlGroup {
                controlIdentifier = id
                XCTAssertEqual(r.variantId, "0")
                break
            }
        }
        XCTAssertNotNil(controlIdentifier)

        let controlRows = evaluator.evaluateAll(request: IdentityMapTestHelpers.request(namespace: IdentityMapTestHelpers.defaultCohortingNamespace, id: controlIdentifier!))
        XCTAssertEqual(controlRows.count, 1)
        XCTAssertEqual(controlRows[0].id, FlagConstants.Policy.CONTROL_GROUP_FEATURE_ID)
        XCTAssertEqual(controlRows[0].analyticsParam?.variantId, "0")

        var treatmentIdentifier: String?
        for i in 0..<250_000 {
            let id = "murmur-treat_\(i)"
            let r = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 10002, identifier: id)
            if !r.controlGroup && r.variantId == "9" {
                treatmentIdentifier = id
                break
            }
        }
        XCTAssertNotNil(treatmentIdentifier)
        let treatRows = evaluator.evaluateAll(request: IdentityMapTestHelpers.request(namespace: IdentityMapTestHelpers.defaultCohortingNamespace, id: treatmentIdentifier!))
        XCTAssertEqual(treatRows[0].key, "cohort-x")
        XCTAssertEqual(treatRows[0].analyticsParam?.variantId, "9")
    }
}
