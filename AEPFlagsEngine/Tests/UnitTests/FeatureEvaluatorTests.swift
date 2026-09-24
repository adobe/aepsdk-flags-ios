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

final class FeatureEvaluatorTests: XCTestCase {

    private let clientId = "test-client"
    private var cache: SDKClientCache!
    private var policyCache: PolicyCache!
    private var evaluator: FeatureEvaluator!

    private var featureGroupIdSeq = 0

    override func setUp() {
        super.setUp()
        featureGroupIdSeq = 0
        cache = SDKClientCache()
        policyCache = PolicyCache()
        evaluator = FeatureEvaluator(clientId: clientId, cache: cache, policyCache: policyCache)
    }

    private func nextFeatureGroupId() -> Int {
        featureGroupIdSeq += 1
        return featureGroupIdSeq
    }

    private func emptyRequest() -> GetFeatureRequest { .defaultRequest }

    private func requestWithContext(_ ctx: [String: [String]]) -> GetFeatureRequest {
        GetFeatureRequest.builder().context(ctx).build()
    }

    private func requestWithNamespaceIdentity(_ namespace: String, _ id: String) -> GetFeatureRequest {
        IdentityMapTestHelpers.request(namespace: namespace, id: id)
    }

    private func requestWithIdentityMap(_ identityMap: [String: [[String: Any]]]) -> GetFeatureRequest {
        IdentityMapTestHelpers.request(identityMap: identityMap)
    }

    private func enableFeatureGroupBucketing(_ featureGroup: FeaturesResponse) {
        featureGroup.params = IdentityMapTestHelpers.ecidBucketingParams()
    }

    private func putFeatureGroups(_ featureGroups: FeaturesResponse...) {
        cache.putFeatures(clientId: clientId, features: Array(featureGroups), etag: "etag-1")
    }

    private func filterService(_ pairs: String...) -> FilterService {
        var m: [String: String] = [:]
        var i = 0
        while i + 1 < pairs.count {
            m[pairs[i]] = pairs[i + 1]
            i += 2
        }
        return FilterService(fieldDataTypeCache: m)
    }

    private func featureGroupStrings(_ name: String, _ feats: String...) -> FeaturesResponse {
        let r = FeaturesResponse()
        r.featureGroupId = nextFeatureGroupId()
        r.featureGroupName = name
        r.features = Array(feats)
        return r
    }

    private func featureGroupObjects(_ name: String, _ feats: Feature...) -> FeaturesResponse {
        let r = FeaturesResponse()
        r.featureGroupId = nextFeatureGroupId()
        r.featureGroupName = name
        r.featuresObj = Array(feats)
        return r
    }

    private func featureGroupIdFeatures(_ id: Int, _ name: String, _ feats: Feature...) -> FeaturesResponse {
        let r = FeaturesResponse()
        r.featureGroupId = id
        r.featureGroupName = name
        r.featuresObj = Array(feats)
        return r
    }

    private func featureGroupIdStrings(_ id: Int, _ name: String, _ names: String...) -> FeaturesResponse {
        let r = FeaturesResponse()
        r.featureGroupId = id
        r.featureGroupName = name
        r.features = Array(names)
        return r
    }

    private func featureNamed(_ n: String) -> Feature {
        let f = Feature()
        f.feature = n
        return f
    }

    private func featureValue(_ n: String, _ v: Any) -> Feature {
        let f = Feature()
        f.feature = n
        f.value = v
        return f
    }

    private func featureCriteria(_ n: String, _ c: String) -> Feature {
        let f = Feature()
        f.feature = n
        f.criteria = c
        return f
    }

    private func featureId(_ n: String, _ id: Int) -> Feature {
        let f = Feature()
        f.feature = n
        f.id = id
        return f
    }

    private func featurePolicy(_ n: String, _ pid: Int) -> Feature {
        let f = Feature()
        f.feature = n
        f.policyId = pid
        return f
    }

    // MARK: - Empty cache

    func testEvaluateAllNoCache() {
        XCTAssertEqual(evaluator.evaluateAll(request: emptyRequest()).count, 0)
    }

    func testEvaluateNoCache() {
        XCTAssertNil(evaluator.evaluate(featureName: "any-feature", request: emptyRequest()))
    }

    func testIsEnabledNoCache() {
        XCTAssertFalse(evaluator.isEnabled(featureName: "any-feature", request: emptyRequest()))
    }

    // MARK: - String features

    func testStringFeatures() {
        putFeatureGroups(featureGroupStrings("R1", "feat-a", "feat-b"))
        let keys = Set(evaluator.evaluateAll(request: emptyRequest()).compactMap { $0.key })
        XCTAssertEqual(keys, ["feat-a", "feat-b"])
    }

    func testEvaluateByName() {
        putFeatureGroups(featureGroupStrings("R1", "feat-a", "feat-b"))
        XCTAssertEqual(evaluator.evaluate(featureName: "feat-b", request: emptyRequest())?.key, "feat-b")
    }

    func testIsEnabledStringFeature() {
        putFeatureGroups(featureGroupStrings("R1", "feat-a"))
        XCTAssertTrue(evaluator.isEnabled(featureName: "feat-a", request: emptyRequest()))
    }

    func testIsEnabledUnknownFeature() {
        putFeatureGroups(featureGroupStrings("R1", "feat-a"))
        XCTAssertFalse(evaluator.isEnabled(featureName: "nonexistent", request: emptyRequest()))
    }

    // MARK: - Basic feature objects

    func testAllFeaturesReturned() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("dark-mode"), featureNamed("new-nav")))
        let keys = Set(evaluator.evaluateAll(request: emptyRequest()).compactMap { $0.key })
        XCTAssertEqual(keys, ["dark-mode", "new-nav"])
    }

    func testFeatureValueCarried() {
        putFeatureGroups(featureGroupObjects("R1", featureValue("dark-mode", "variant-a")))
        let r = evaluator.evaluateAll(request: emptyRequest())
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].value as? String, "variant-a")
    }

    // MARK: - FeatureGroup name

    func testFeatureGroupNameStamped() {
        putFeatureGroups(featureGroupObjects("FeatureGroup_V2", featureNamed("dark-mode")))
        let r = evaluator.evaluateAll(request: emptyRequest())
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].featureGroupKey, "FeatureGroup_V2")
    }

    func testFeatureGroupNameOnStringFeatures() {
        putFeatureGroups(featureGroupStrings("Beta_FeatureGroup", "feat-a"))
        let r = evaluator.evaluateAll(request: emptyRequest())
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].featureGroupKey, "Beta_FeatureGroup")
    }

    func testMultipleFeatureGroupsStamped() {
        putFeatureGroups(featureGroupStrings("R1", "feat-a"), featureGroupObjects("R2", featureNamed("feat-b")))
        let byKey = Dictionary(uniqueKeysWithValues: evaluator.evaluateAll(request: emptyRequest()).map { ($0.key ?? "", $0.featureGroupKey) })
        XCTAssertEqual(byKey["feat-a"], "R1")
        XCTAssertEqual(byKey["feat-b"], "R2")
    }

    // MARK: - Multiple featureGroups aggregation

    func testAggregation() {
        putFeatureGroups(
            featureGroupStrings("R1", "feat-a"),
            featureGroupObjects("R2", featureNamed("feat-b")),
            featureGroupStrings("R3", "feat-c")
        )
        let keys = Set(evaluator.evaluateAll(request: emptyRequest()).compactMap { $0.key })
        XCTAssertEqual(keys, ["feat-a", "feat-b", "feat-c"])
    }

    // MARK: - FeatureGroup criteria

    func testFeatureGroupCriteriaMatch() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let rel = featureGroupStrings("R1", "feat-a")
        rel.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        putFeatureGroups(rel)
        let r = evaluator.evaluateAll(request: requestWithContext(["country": ["US"]]))
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].key, "feat-a")
    }

    func testFeatureGroupCriteriaNoMatch() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let rel = featureGroupStrings("R1", "feat-a")
        rel.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        putFeatureGroups(rel)
        XCTAssertEqual(evaluator.evaluateAll(request: requestWithContext(["country": ["UK"]])).count, 0)
    }

    func testFeatureGroupEmptyCriteriaIncluded() {
        let rel = featureGroupStrings("R1", "feat-a")
        rel.criteria = ""
        putFeatureGroups(rel)
        XCTAssertEqual(evaluator.evaluateAll(request: emptyRequest()).count, 1)
    }

    func testFeatureGroupNullCriteriaIncluded() {
        let rel = featureGroupStrings("R1", "feat-a")
        rel.criteria = nil
        putFeatureGroups(rel)
        XCTAssertEqual(evaluator.evaluateAll(request: emptyRequest()).count, 1)
    }

    // MARK: - Feature criteria

    func testFeatureCriteriaFiltering() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let f1 = featureCriteria("us-only", #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#)
        let f2 = featureCriteria("uk-only", #"{"criteria": {"attr": "country", "operator": "EQ", "val": "UK"}}"#)
        let f3 = featureNamed("global")
        putFeatureGroups(featureGroupObjects("R1", f1, f2, f3))
        let keys = Set(evaluator.evaluateAll(request: requestWithContext(["country": ["US"]])).compactMap { $0.key })
        XCTAssertEqual(keys, ["us-only", "global"])
    }

    func testFeatureCriteriaExclusion() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let f = featureCriteria("premium-only", #"{"criteria": {"attr": "country", "operator": "EQ", "val": "JP"}}"#)
        putFeatureGroups(featureGroupObjects("R1", f))
        XCTAssertEqual(evaluator.evaluateAll(request: requestWithContext(["country": ["US"]])).count, 0)
    }

    // MARK: - Relational operators

    func testGtDecimalThroughEvaluator() {
        evaluator.setFilterService(filterService("metric", "DECIMAL", "days", "INTEGER"))
        let f = featureCriteria("rel-gt", #"{"criteria":{"attr":"metric","operator":"GT","val":10}}"#)
        f.id = 501
        putFeatureGroups(featureGroupObjects("R-rel", f))
        let above = requestWithContext(["metric": ["16.4"]])
        XCTAssertEqual(evaluator.evaluateAll(request: above).count, 1)
        XCTAssertNotNil(evaluator.evaluate(featureName: "rel-gt", request: above))
        XCTAssertTrue(evaluator.isEnabled(featureName: "rel-gt", request: above))
        let at = requestWithContext(["metric": ["10"]])
        XCTAssertEqual(evaluator.evaluateAll(request: at).count, 0)
        XCTAssertNil(evaluator.evaluate(featureName: "rel-gt", request: at))
    }

    func testLtIntegerThroughEvaluator() {
        evaluator.setFilterService(filterService("metric", "DECIMAL", "days", "INTEGER"))
        let f = featureCriteria("rel-lt", #"{"criteria":{"attr":"days","operator":"LT","val":20}}"#)
        f.id = 502
        putFeatureGroups(featureGroupObjects("R-rel", f))
        let below = requestWithContext(["days": ["5"]])
        XCTAssertEqual(evaluator.evaluateAll(request: below).count, 1)
        let at = requestWithContext(["days": ["20"]])
        XCTAssertEqual(evaluator.evaluateAll(request: at).count, 0)
    }

    func testGeDecimalThroughEvaluator() {
        evaluator.setFilterService(filterService("metric", "DECIMAL", "days", "INTEGER"))
        let f = featureCriteria("rel-ge", #"{"criteria":{"attr":"metric","operator":"GE","val":15.8}}"#)
        f.id = 503
        putFeatureGroups(featureGroupObjects("R-rel", f))
        let eq = requestWithContext(["metric": ["15.8"]])
        XCTAssertEqual(evaluator.evaluateAll(request: eq).count, 1)
        let below = requestWithContext(["metric": ["15.7"]])
        XCTAssertEqual(evaluator.evaluateAll(request: below).count, 0)
    }

    func testLeIntegerThroughEvaluator() {
        evaluator.setFilterService(filterService("metric", "DECIMAL", "days", "INTEGER"))
        let f = featureCriteria("rel-le", #"{"criteria":{"attr":"days","operator":"LE","val":10}}"#)
        f.id = 504
        putFeatureGroups(featureGroupObjects("R-rel", f))
        let eq = requestWithContext(["days": ["10"]])
        XCTAssertEqual(evaluator.evaluateAll(request: eq).count, 1)
        let above = requestWithContext(["days": ["11"]])
        XCTAssertEqual(evaluator.evaluateAll(request: above).count, 0)
    }

    // MARK: - No filter service

    func testFeatureGroupCriteriaIgnoredWithoutFilterService() {
        let rel = featureGroupStrings("R1", "feat-a")
        rel.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        putFeatureGroups(rel)
        XCTAssertEqual(evaluator.evaluateAll(request: emptyRequest()).count, 0)
    }

    func testFeatureCriteriaIgnoredWithoutFilterService() {
        let f = featureCriteria("feat-a", #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#)
        putFeatureGroups(featureGroupObjects("R1", f))
        XCTAssertEqual(evaluator.evaluateAll(request: emptyRequest()).count, 0)
    }

    // MARK: - FeatureGroup policy (uncached fallback split)

    func testFeatureGroupPolicyControlGroupExists() {
        let rel = featureGroupStrings("R1", "feat-a")
        rel.policyId = 999
        enableFeatureGroupBucketing(rel)
        putFeatureGroups(rel)
        var anyExcluded = false
        for i in 0..<100 {
            let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"control-test-\(i)")
            if evaluator.evaluateAll(request: req).isEmpty { anyExcluded = true; break }
        }
        XCTAssertTrue(anyExcluded)
    }

    func testFeatureGroupPolicyTreatmentGroupExists() {
        let rel = featureGroupStrings("R1", "feat-a")
        rel.policyId = 999
        enableFeatureGroupBucketing(rel)
        putFeatureGroups(rel)
        var anyIncluded = false
        for i in 0..<100 {
            let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"treatment-test-\(i)")
            if !evaluator.evaluateAll(request: req).isEmpty { anyIncluded = true; break }
        }
        XCTAssertTrue(anyIncluded)
    }

    func testNullFeatureGroupPolicyAlwaysIncluded() {
        let rel = featureGroupStrings("R1", "feat-a")
        rel.policyId = nil
        putFeatureGroups(rel)
        XCTAssertEqual(evaluator.evaluateAll(request: emptyRequest()).count, 1)
    }

    // MARK: - Feature policy

    func testFeaturePolicyControlSentinelExists() {
        let f = featurePolicy("ab-feature", 888)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        putFeatureGroups(featureGroupObjects("R1", f))
        var saw = false
        for i in 0..<200 {
            let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"fp-control-\(i)")
            let rows = evaluator.evaluateAll(request: req)
            XCTAssertEqual(rows.count, 1)
            let row = rows[0]
            if row.key == nil && row.id == FlagConstants.Policy.CONTROL_GROUP_FEATURE_ID {
                XCTAssertNotNil(row.analyticsParam)
                XCTAssertFalse(evaluator.isEnabled(featureName: "ab-feature", request: req))
                saw = true
                break
            }
        }
        XCTAssertTrue(saw)
    }

    func testFeatureNullPolicyAlwaysIncluded() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("no-policy")))
        XCTAssertEqual(evaluator.evaluateAll(request: emptyRequest()).count, 1)
    }

    // MARK: - Cached policy bucketing

    func testFeatureGroupPolicyFromCache() {
        let buckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 2999, percentage: 30),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 3000, endRange: 9999, percentage: 70)
        ]
        let detail = PolicyCache.PolicyDetail(id: 500, hashAlgorithmType: "MURMUR_HASH", seed: "500", buckets: buckets, previewUserVariantMap: nil)
        policyCache.put(detail, for: 500)
        let rel = featureGroupStrings("R1", "feat-a")
        rel.policyId = 500
        enableFeatureGroupBucketing(rel)
        putFeatureGroups(rel)
        var control = 0
        let total = 5000
        for i in 0..<total {
            let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"user_\(i)")
            if evaluator.evaluateAll(request: req).isEmpty { control += 1 }
        }
        let pct = Double(control) * 100.0 / Double(total)
        XCTAssertGreaterThan(pct, 25)
        XCTAssertLessThan(pct, 35)
    }

    func testFeaturePolicyFromCache() {
        let buckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 5000, endRange: 9999, percentage: 50)
        ]
        let detail = PolicyCache.PolicyDetail(id: 600, hashAlgorithmType: "MURMUR_HASH", seed: "600", buckets: buckets, previewUserVariantMap: nil)
        policyCache.put(detail, for: 600)
        let f = featurePolicy("ab-feature", 600)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        putFeatureGroups(featureGroupObjects("R1", f))
        var control = 0
        let total = 5000
        for i in 0..<total {
            let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"user_\(i)")
            let rows = evaluator.evaluateAll(request: req)
            XCTAssertEqual(rows.count, 1)
            if rows[0].key == nil { control += 1 }
        }
        let pct = Double(control) * 100.0 / Double(total)
        XCTAssertGreaterThan(pct, 45)
        XCTAssertLessThan(pct, 55)
    }

    func testPolicyCachePipelineEndToEnd() {
        let buckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 2999, percentage: 30),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 3000, endRange: 9999, percentage: 70)
        ]
        let detail = PolicyCache.PolicyDetail(id: 700, hashAlgorithmType: "MURMUR_HASH", seed: "700", buckets: buckets, previewUserVariantMap: nil)
        let rel = featureGroupObjects("R1", featureNamed("feat-a"))
        rel.policyId = 700
        rel.policy = detail
        enableFeatureGroupBucketing(rel)
        if let pid = rel.policyId, let pol = rel.policy {
            policyCache.put(pol, for: pid)
        }
        putFeatureGroups(rel)
        var control = 0
        for i in 0..<5000 {
            let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"user_\(i)")
            if evaluator.evaluateAll(request: req).isEmpty { control += 1 }
        }
        let pct = Double(control) * 100.0 / 5000.0
        XCTAssertGreaterThan(pct, 25)
        XCTAssertLessThan(pct, 35)
    }

    // MARK: - Identity map bucketing

    func testDeterministicBucketing() {
        let f = featurePolicy("ab-test", 777)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        putFeatureGroups(featureGroupObjects("R1", f))
        let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace, "stable-bucket-42")
        let first = evaluator.isEnabled(featureName: "ab-test", request: req)
        for _ in 0..<50 {
            XCTAssertEqual(first, evaluator.isEnabled(featureName: "ab-test", request: req))
        }
    }

    func testDifferentIdentityIdsCanDiffer() {
        let f = featurePolicy("ab-test", 555)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        putFeatureGroups(featureGroupObjects("R1", f))
        var seenTrue = false
        var seenFalse = false
        for i in 0..<200 {
            let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace, "bucket-\(i)")
            if evaluator.isEnabled(featureName: "ab-test", request: req) { seenTrue = true } else { seenFalse = true }
        }
        XCTAssertTrue(seenTrue && seenFalse)
    }

    func testBucketingUsesIdentityMapId() {
        policyCache.put(PolicyCache.PolicyDetail(id: 801,
                                                 hashAlgorithmType: "MURMUR_HASH",
                                                 seed: "801",
                                                 buckets: [
                                                    PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
                                                    PolicyCache.PolicyBucket(variantId: "1", startRange: 5000, endRange: 9999, percentage: 50)
                                                 ],
                                                 previewUserVariantMap: nil), for: 801)
        let f = featurePolicy("id-map-test", 801)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        putFeatureGroups(featureGroupObjects("R1", f))
        let identityId = "abc123"
        let req = requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace, identityId)
        let expected = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 801, identifier: identityId)
        XCTAssertEqual(!expected.controlGroup, evaluator.isEnabled(featureName: "id-map-test", request: req))
    }

    func testFeaturePolicyUsesFeatureCohortingNamespace() {
        policyCache.put(PolicyCache.PolicyDetail(id: 902,
                                                 hashAlgorithmType: "MURMUR_HASH",
                                                 seed: "902",
                                                 buckets: [
                                                    PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
                                                    PolicyCache.PolicyBucket(variantId: "1", startRange: 5000, endRange: 9999, percentage: 50)
                                                 ],
                                                 previewUserVariantMap: nil), for: 902)

        var stickyId: String?
        var ecidId: String?
        for i in 0..<200_000 {
            let candidate = "cohort-seek_\(i)"
            let response = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 902, identifier: candidate)
            if response.controlGroup && ecidId == nil { ecidId = candidate }
            else if !response.controlGroup && stickyId == nil { stickyId = candidate }
            if stickyId != nil && ecidId != nil { break }
        }
        XCTAssertNotNil(stickyId)
        XCTAssertNotNil(ecidId)

        let f = featurePolicy("cohort-ns-test", 902)
        f.params = [
            FlagConstants.JSONKeys.COHORTING_TYPE: CohortingType.sticky.rawString,
            FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE: CohortingType.sticky.rawString
        ]
        let featureGroup = featureGroupObjects("R1", f)
        featureGroup.params = [
            FlagConstants.JSONKeys.COHORTING_TYPE: CohortingType.ecid.rawString,
            FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE: CohortingType.ecid.rawString
        ]
        putFeatureGroups(featureGroup)

        let identityMap: [String: [[String: Any]]] = [
            CohortingType.ecid.rawString: [IdentityMapTestHelpers.identityEntry(id: ecidId!, primary: true)],
            CohortingType.sticky.rawString: [IdentityMapTestHelpers.identityEntry(id: stickyId!, primary: true)]
        ]
        let req = requestWithIdentityMap(identityMap)
        let wouldBeFromEcid = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 902, identifier: ecidId!)
        XCTAssertTrue(wouldBeFromEcid.controlGroup)
        XCTAssertTrue(evaluator.isEnabled(featureName: "cohort-ns-test", request: req))
    }

    func testFeaturePolicyUsesCustomCohortingNamespaceCode() {
        policyCache.put(PolicyCache.PolicyDetail(id: 903,
                                                 hashAlgorithmType: "MURMUR_HASH",
                                                 seed: "903",
                                                 buckets: [
                                                    PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
                                                    PolicyCache.PolicyBucket(variantId: "1", startRange: 5000, endRange: 9999, percentage: 50)
                                                 ],
                                                 previewUserVariantMap: nil), for: 903)

        var loginId: String?
        for i in 0..<200_000 {
            let candidate = "login-seek_\(i)"
            let response = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 903, identifier: candidate)
            if !response.controlGroup {
                loginId = candidate
                break
            }
        }
        XCTAssertNotNil(loginId)

        let f = featurePolicy("login-id-test", 903)
        f.params = [
            FlagConstants.JSONKeys.COHORTING_TYPE: CohortingType.sticky.rawString,
            FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE: "loginID"
        ]
        putFeatureGroups(featureGroupObjects("R1", f))

        let identityMap: [String: [[String: Any]]] = [
            "loginID": [IdentityMapTestHelpers.identityEntry(id: loginId!, primary: true)],
            CohortingType.sticky.rawString: [IdentityMapTestHelpers.identityEntry(id: "wrong-sticky-id", primary: true)]
        ]
        XCTAssertTrue(evaluator.isEnabled(featureName: "login-id-test", request: requestWithIdentityMap(identityMap)))
    }

    // MARK: - Name lookup

    func testFindByName() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("alpha"), featureNamed("beta"), featureNamed("gamma")))
        XCTAssertEqual(evaluator.evaluate(featureName: "beta", request: emptyRequest())?.key, "beta")
    }

    func testUnknownName() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("alpha")))
        XCTAssertNil(evaluator.evaluate(featureName: "nonexistent", request: emptyRequest()))
    }

    func testNullName() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("alpha")))
        XCTAssertNil(evaluator.evaluate(featureName: nil, request: emptyRequest()))
    }

    func testIsEnabledExisting() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("alpha")))
        XCTAssertTrue(evaluator.isEnabled(featureName: "alpha", request: emptyRequest()))
    }

    func testIsEnabledUnknown() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("alpha")))
        XCTAssertFalse(evaluator.isEnabled(featureName: "nonexistent", request: emptyRequest()))
    }

    // MARK: - Targeted evaluation

    func testEvaluateConsistentWithEvaluateAll() {
        putFeatureGroups(featureGroupIdFeatures(100, "R1", featureId("alpha", 1), featureId("beta", 2), featureId("gamma", 3)))
        let targeted = evaluator.evaluate(featureName: "beta", request: emptyRequest())!
        XCTAssertEqual(targeted.key, "beta")
        XCTAssertEqual(targeted.id, 2)
        XCTAssertEqual(targeted.featureGroupKey, "R1")
        let fromAll = evaluator.evaluateAll(request: emptyRequest()).first { $0.key == "beta" }
        XCTAssertEqual(fromAll?.id, targeted.id)
        XCTAssertEqual(fromAll?.featureGroupKey, targeted.featureGroupKey)
    }

    func testEvaluateAcrossFeatureGroups() {
        putFeatureGroups(
            featureGroupIdFeatures(10, "R1", featureId("alpha", 1)),
            featureGroupIdFeatures(20, "R2", featureId("beta", 2)),
            featureGroupIdFeatures(30, "R3", featureId("gamma", 3))
        )
        let r = evaluator.evaluate(featureName: "gamma", request: emptyRequest())!
        XCTAssertEqual(r.analyticsParam?.featureGroupId, 30)
    }

    func testEvaluateSkipsUnrelatedFeatureGroups() {
        putFeatureGroups(
            featureGroupIdFeatures(10, "R1", featureId("alpha", 1)),
            featureGroupIdFeatures(20, "R2", featureId("beta", 2)),
            featureGroupIdFeatures(30, "R3", featureId("gamma", 3))
        )
        let r = evaluator.evaluate(featureName: "gamma", request: emptyRequest())!
        XCTAssertEqual(r.analyticsParam?.featureGroupId, 30)
        XCTAssertEqual(r.id, 3)
    }

    func testEvaluateRespectsFeatureGroupCriteria() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let rel = featureGroupIdFeatures(10, "R1", featureId("feat-a", 1))
        rel.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        putFeatureGroups(rel)
        XCTAssertNil(evaluator.evaluate(featureName: "feat-a", request: requestWithContext(["country": ["UK"]])))
        XCTAssertNotNil(evaluator.evaluate(featureName: "feat-a", request: requestWithContext(["country": ["US"]])))
    }

    func testEvaluateRespectsFeatureCriteria() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let feat = featureCriteria("us-only", #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#)
        feat.id = 42
        putFeatureGroups(featureGroupObjects("R1", feat, featureNamed("global")))
        XCTAssertNil(evaluator.evaluate(featureName: "us-only", request: requestWithContext(["country": ["UK"]])))
        XCTAssertNotNil(evaluator.evaluate(featureName: "us-only", request: requestWithContext(["country": ["US"]])))
        XCTAssertNotNil(evaluator.evaluate(featureName: "global", request: requestWithContext(["country": ["UK"]])))
    }

    func testEvaluateStringFeature() {
        putFeatureGroups(featureGroupIdStrings(50, "R1", "feat-a", "feat-b", "feat-c"))
        let r = evaluator.evaluate(featureName: "feat-b", request: emptyRequest())!
        XCTAssertEqual(r.analyticsParam?.featureGroupId, 50)
    }

    func testEvaluateStringFeatureMissing() {
        putFeatureGroups(featureGroupIdStrings(50, "R1", "feat-a", "feat-b"))
        XCTAssertNil(evaluator.evaluate(featureName: "feat-c", request: emptyRequest()))
    }

    func testEvaluateAnalyticsParam() {
        putFeatureGroups(featureGroupIdFeatures(100, "R1", featureId("dark-mode", 42), featureId("new-nav", 43)))
        let r = evaluator.evaluate(featureName: "dark-mode", request: emptyRequest())!
        XCTAssertEqual(r.analyticsParam?.featureGroupId, 100)
        XCTAssertEqual(r.analyticsParam?.featureId, 42)
        XCTAssertEqual(r.analyticsParam?.featureKey, "dark-mode")
    }

    func testIsEnabledNullName() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("alpha")))
        XCTAssertFalse(evaluator.isEnabled(featureName: nil, request: emptyRequest()))
    }

    // MARK: - Combined criteria + policy

    func testCriteriaBlocksBeforePolicy() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let rel = featureGroupStrings("R1", "feat-a")
        rel.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        rel.policyId = nil
        putFeatureGroups(rel)
        XCTAssertEqual(evaluator.evaluateAll(request: requestWithContext(["country": ["UK"]])).count, 0)
    }

    func testMixedFeatureGroupsCriteriaAndPolicy() {
        evaluator.setFilterService(filterService("country", "STRING"))
        let m = featureGroupStrings("R1", "visible")
        m.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        let b = featureGroupStrings("R2", "hidden")
        b.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "UK"}}"#
        putFeatureGroups(m, b)
        let r = evaluator.evaluateAll(request: requestWithContext(["country": ["US"]]))
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].key, "visible")
    }

    // MARK: - AnalyticsParam

    func testAnalyticsParamOnFeatureObjects() {
        putFeatureGroups(featureGroupIdFeatures(100, "R1", featureId("dark-mode", 42)))
        let r = evaluator.evaluateAll(request: emptyRequest())
        XCTAssertEqual(r.count, 1)
        let p = r[0].analyticsParam!
        XCTAssertEqual(p.featureGroupId, 100)
        XCTAssertEqual(p.featureId, 42)
        XCTAssertEqual(p.featureKey, "dark-mode")
        XCTAssertNil(p.variantId)
    }

    func testAnalyticsParamOnStringFeatures() {
        putFeatureGroups(featureGroupIdStrings(200, "R2", "feat-a"))
        let r = evaluator.evaluateAll(request: emptyRequest())
        XCTAssertEqual(r.count, 1)
        let p = r[0].analyticsParam!
        XCTAssertEqual(p.featureGroupId, 200)
        XCTAssertEqual(p.featureId, 0)
        XCTAssertEqual(p.featureKey, "feat-a")
        XCTAssertNil(p.variantId)
    }

    func testFeatureGroupPolicyVariantIdPopulated() {
        let buckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 0, percentage: 0),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 1, endRange: 9999, percentage: 100)
        ]
        policyCache.put(PolicyCache.PolicyDetail(id: 300, hashAlgorithmType: "MURMUR_HASH", seed: "300", buckets: buckets, previewUserVariantMap: nil), for: 300)
        let rel = featureGroupIdStrings(50, "R1", "feat-a")
        rel.policyId = 300
        enableFeatureGroupBucketing(rel)
        putFeatureGroups(rel)
        var foundVariant: String?
        for i in 0..<100_000 {
            let r = evaluator.evaluateAll(request: requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"v-\(i)"))
            if r.count == 1, let v = r[0].analyticsParam?.variantId, !v.isEmpty {
                foundVariant = v
                break
            }
        }
        XCTAssertNotNil(foundVariant)
    }

    func testFeaturePolicyOverridesFeatureGroupVariantId() {
        let featureGroupBuckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 0, percentage: 0),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 1, endRange: 9999, percentage: 100)
        ]
        policyCache.put(PolicyCache.PolicyDetail(id: 400, hashAlgorithmType: "MURMUR_HASH", seed: "400", buckets: featureGroupBuckets, previewUserVariantMap: nil), for: 400)
        let featureBuckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 0, percentage: 0),
            PolicyCache.PolicyBucket(variantId: "5", startRange: 1, endRange: 9999, percentage: 100)
        ]
        policyCache.put(PolicyCache.PolicyDetail(id: 401, hashAlgorithmType: "MURMUR_HASH", seed: "401", buckets: featureBuckets, previewUserVariantMap: nil), for: 401)
        let f = featureIdAndPolicy("feat-a", 10, 401)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        let rel = featureGroupIdFeatures(60, "R1", f)
        rel.policyId = 400
        enableFeatureGroupBucketing(rel)
        putFeatureGroups(rel)
        var sawFive = false
        for i in 0..<100_000 {
            let r = evaluator.evaluateAll(request: requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"fv-\(i)"))
            if r.count == 1, r[0].analyticsParam?.variantId == "5" {
                sawFive = true
                break
            }
        }
        XCTAssertTrue(sawFive, "expected a visitor where feature policy variant 5 wins over featureGroup policy")
    }

    // MARK: - Control variant analytics

    private func findVisitorIdWithPolicyControlOutcome(_ policyId: Int) -> String? {
        for i in 0..<200_000 {
            let vid = "ctrl-seek_\(i)"
            let r = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: policyId, identifier: vid)
            if r.controlGroup { return vid }
        }
        return nil
    }

    func testEmptyControlBucketAnalyticsUsesZero() {
        policyCache.put(
            PolicyCache.PolicyDetail(id: 9101, hashAlgorithmType: "MURMUR_HASH", seed: "feat-seed-9101",
                                      buckets: [
                                        PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
                                        PolicyCache.PolicyBucket(variantId: "3", startRange: 5000, endRange: 9999, percentage: 50)
                                      ],
                                      previewUserVariantMap: nil),
            for: 9101)
        let f = featureIdAndPolicy("gated-feat", 50, 9101)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        putFeatureGroups(featureGroupIdFeatures(200, "R1", f))
        let vid = findVisitorIdWithPolicyControlOutcome(9101)
        XCTAssertNotNil(vid)
        let rows = evaluator.evaluateAll(request: requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,vid!))
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.id, FlagConstants.Policy.CONTROL_GROUP_FEATURE_ID)
        XCTAssertNil(row.key)
        XCTAssertEqual(row.analyticsParam?.variantId, "0")
    }

    func testExplicitZeroControlBucketAnalyticsUsesZero() {
        policyCache.put(
            PolicyCache.PolicyDetail(id: 9102, hashAlgorithmType: "MURMUR_HASH", seed: "feat-seed-9102",
                                      buckets: [PolicyCache.PolicyBucket(variantId: "0", startRange: 0, endRange: 9999, percentage: 100)],
                                      previewUserVariantMap: nil),
            for: 9102)
        let f = featureIdAndPolicy("flag-z", 99, 9102)
        f.params = IdentityMapTestHelpers.ecidBucketingParams()
        putFeatureGroups(featureGroupIdFeatures(201, "R1", f))
        let rows = evaluator.evaluateAll(request: requestWithNamespaceIdentity(IdentityMapTestHelpers.defaultCohortingNamespace,"any-fixed-visitor"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, FlagConstants.Policy.CONTROL_GROUP_FEATURE_ID)
        XCTAssertNil(rows[0].key)
        XCTAssertEqual(rows[0].analyticsParam?.variantId, "0")
    }

    // MARK: - Thread safety

    func testConcurrentEvaluateAllConsistent() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("feat-a"), featureNamed("feat-b"), featureNamed("feat-c")))
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            for _ in 0..<500 {
                let results = evaluator.evaluateAll(request: emptyRequest())
                XCTAssertEqual(results.count, 3)
                let keys = Set(results.compactMap { $0.key })
                XCTAssertEqual(keys, ["feat-a", "feat-b", "feat-c"])
            }
        }
    }

    func testConcurrentEvaluateAndIsEnabled() {
        putFeatureGroups(featureGroupObjects("R1", featureNamed("alpha"), featureNamed("beta")))
        DispatchQueue.concurrentPerform(iterations: 16) { idx in
            for _ in 0..<500 {
                if idx % 2 == 0 {
                    let r = self.evaluator.evaluate(featureName: "alpha", request: self.emptyRequest())
                    XCTAssertNotNil(r)
                    XCTAssertEqual(r?.key, "alpha")
                } else {
                    XCTAssertTrue(self.evaluator.isEnabled(featureName: "beta", request: self.emptyRequest()))
                    XCTAssertFalse(self.evaluator.isEnabled(featureName: "nonexistent", request: self.emptyRequest()))
                }
            }
        }
    }

    func testFilterServiceVisibleToConcurrentEvaluations() {
        let rel = featureGroupStrings("R1", "feat-a")
        rel.criteria = #"{"criteria": {"attr": "country", "operator": "EQ", "val": "US"}}"#
        putFeatureGroups(rel)
        XCTAssertEqual(evaluator.evaluateAll(request: requestWithContext(["country": ["US"]])).count, 0)
        evaluator.setFilterService(filterService("country", "STRING"))
        var usMatches = 0
        var ukMatches = 0
        DispatchQueue.concurrentPerform(iterations: 10) { t in
            let useUS = t % 2 == 0
            for _ in 0..<200 {
                let results = self.evaluator.evaluateAll(request: useUS
                    ? self.requestWithContext(["country": ["US"]])
                    : self.requestWithContext(["country": ["UK"]]))
                if useUS {
                    XCTAssertEqual(results.count, 1)
                    usMatches += 1
                } else {
                    XCTAssertEqual(results.count, 0)
                    ukMatches += 1
                }
            }
        }
        XCTAssertGreaterThan(usMatches, 0)
        XCTAssertGreaterThan(ukMatches, 0)
    }

    func testEvaluateEmptyStringFeatureName() {
        putFeatureGroups(featureGroupStrings("R1", ""))
        let result = evaluator.evaluate(featureName: "", request: emptyRequest())
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "")
    }

    private func featureIdAndPolicy(_ name: String, _ id: Int, _ policyId: Int) -> Feature {
        let f = Feature()
        f.feature = name
        f.id = id
        f.policyId = policyId
        return f
    }
}
