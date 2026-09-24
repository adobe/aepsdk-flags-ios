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

final class PolicyEvaluatorTests: XCTestCase {

    private var policyCache: PolicyCache!

    override func setUp() {
        super.setUp()
        policyCache = PolicyCache()
    }

    func testDeterministicBucketing() {
        let identifier = "user123"
        let policyId = 100
        let r1 = PolicyEvaluator.getPolicyVariant(policyId: policyId, identifier: identifier, controlPercentage: 50)
        let r2 = PolicyEvaluator.getPolicyVariant(policyId: policyId, identifier: identifier, controlPercentage: 50)
        let r3 = PolicyEvaluator.getPolicyVariant(policyId: policyId, identifier: identifier, controlPercentage: 50)
        XCTAssertEqual(r1.variantId, r2.variantId)
        XCTAssertEqual(r2.variantId, r3.variantId)
        XCTAssertEqual(r1.controlGroup, r2.controlGroup)
    }

    func testDistribution() {
        let policyId = 100
        let controlPercentage = 50
        let totalUsers = 10_000
        var controlCount = 0
        for i in 0..<totalUsers {
            let r = PolicyEvaluator.getPolicyVariant(policyId: policyId,
                                                     identifier: "user_\(i)",
                                                     controlPercentage: controlPercentage)
            if r.controlGroup { controlCount += 1 }
        }
        let actualPercentage = Double(controlCount * 100) / Double(totalUsers)
        XCTAssertTrue(actualPercentage > 45 && actualPercentage < 55,
                      "Control group should be ~50%, was: \(actualPercentage)%")
    }

    func testPolicyBuckets() {
        let buckets = [
            PolicyEvaluator.PercentageSplit(variantId: 0, percentage: 30),
            PolicyEvaluator.PercentageSplit(variantId: 1, percentage: 70)
        ]
        var controlCount = 0
        var treatmentCount = 0
        let totalUsers = 10_000
        for i in 0..<totalUsers {
            let r = PolicyEvaluator.getPolicyVariant(policyId: 100, identifier: "user_\(i)", buckets: buckets)
            if r.variantId == "0" {
                controlCount += 1
            } else {
                treatmentCount += 1
            }
        }
        let controlPct = Double(controlCount * 100) / Double(totalUsers)
        let treatmentPct = Double(treatmentCount * 100) / Double(totalUsers)
        XCTAssertTrue(controlPct > 25 && controlPct < 35, "Control should be ~30%, was: \(controlPct)%")
        XCTAssertTrue(treatmentPct > 65 && treatmentPct < 75, "Treatment should be ~70%, was: \(treatmentPct)%")
    }

    func testMurmurHashConsistency() {
        let hash = MurmurHashStrategy()
        let v1 = hash.hash(identifier: "test_user_123", seed: nil)
        let v2 = hash.hash(identifier: "test_user_123", seed: nil)
        let v3 = hash.hash(identifier: "test_user_123", seed: nil)
        XCTAssertEqual(v1, v2)
        XCTAssertEqual(v2, v3)
    }

    func testMurmurHashWithSeed() {
        let hash = MurmurHashStrategy()
        let v1 = hash.hash(identifier: "test_user", seed: "seed1")
        let v2 = hash.hash(identifier: "test_user", seed: "seed2")
        let v3 = hash.hash(identifier: "test_user", seed: "seed3")
        XCTAssertNotEqual(v1, v2)
        XCTAssertNotEqual(v2, v3)
    }

    func testMurmurHashRange() {
        let hash = MurmurHashStrategy()
        for i in 0..<1000 {
            let value = hash.hash(identifier: "user_\(i)", seed: nil)
            XCTAssertTrue(value >= 0 && value < 10_000, "Hash should be 0-9999, was: \(value)")
        }
    }

    /// Golden MurmurHash vectors for bucketing consistency.
    func testMurmurHashGoldenVectors() {
        let hash = MurmurHashStrategy()
        XCTAssertEqual(hash.hash(identifier: "test_user_123", seed: nil), 8737)
        XCTAssertEqual(hash.hash(identifier: "test_user", seed: "seed1"), 7445)
        XCTAssertEqual(hash.hash(identifier: "test_user", seed: "seed2"), 4885)
        XCTAssertEqual(hash.hash(identifier: "user_42", seed: nil), 1883)
        XCTAssertEqual(hash.hash(identifier: "visitor-abc-123", seed: "1778520509074-seed"), 9711)
    }

    func testGetPolicyVariantFromCacheEmptyCache() {
        let r1 = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 100, identifier: "user123")
        XCTAssertFalse(r1.variantId.isEmpty)
        let r2 = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 100, identifier: "user123")
        XCTAssertEqual(r1.variantId, r2.variantId)
        XCTAssertEqual(r1.controlGroup, r2.controlGroup)
    }

    func testGetPolicyVariantFromCacheFallbackDistribution() {
        var controlCount = 0
        let totalUsers = 10_000
        for i in 0..<totalUsers {
            let r = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 100, identifier: "user_\(i)")
            if r.controlGroup { controlCount += 1 }
        }
        let controlPct = Double(controlCount * 100) / Double(totalUsers)
        XCTAssertTrue(controlPct > 45 && controlPct < 55, "Fallback should produce ~50% control, was: \(controlPct)%")
    }

    func testGetPolicyVariantFromCacheWithPopulatedCache() {
        let buckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 2999, percentage: 30),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 3000, endRange: 9999, percentage: 70)
        ]
        let detail = PolicyCache.PolicyDetail(id: 200,
                                              hashAlgorithmType: "murmur",
                                              seed: "200",
                                              buckets: buckets,
                                              previewUserVariantMap: nil)
        policyCache.put(detail, for: 200)

        var controlCount = 0
        let totalUsers = 10_000
        for i in 0..<totalUsers {
            let r = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 200, identifier: "user_\(i)")
            if r.controlGroup { controlCount += 1 }
        }
        let controlPct = Double(controlCount * 100) / Double(totalUsers)
        XCTAssertTrue(controlPct > 25 && controlPct < 35, "Cached policy should produce ~30% control, was: \(controlPct)%")
    }

    func testPolicyDetailOnModels() {
        let buckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 5000, endRange: 9999, percentage: 50)
        ]
        let preview: [String: String] = ["testUser": "1"]
        let detail = PolicyCache.PolicyDetail(id: 42,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "mySeed",
                                              buckets: buckets,
                                              previewUserVariantMap: preview)

        let featureGroup = FeaturesResponse()
        featureGroup.policyId = 42
        featureGroup.policy = detail
        XCTAssertNotNil(featureGroup.policy)
        XCTAssertEqual(featureGroup.policy?.id, 42)
        XCTAssertEqual(featureGroup.policy?.seed, "mySeed")
        XCTAssertEqual(featureGroup.policy?.buckets.count, 2)

        let feature = Feature()
        feature.policyId = 42
        feature.policy = detail
        XCTAssertNotNil(feature.policy)
        XCTAssertEqual(feature.policy?.hashAlgorithmType, "MURMUR_HASH")
        XCTAssertEqual(feature.policy?.previewUserVariantMap?["testUser"], "1")
    }

    func testPolicyCacheFromModelEndToEnd() {
        let buckets = [
            PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
            PolicyCache.PolicyBucket(variantId: "1", startRange: 5000, endRange: 9999, percentage: 50)
        ]
        let detail = PolicyCache.PolicyDetail(id: 300,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "300",
                                              buckets: buckets,
                                              previewUserVariantMap: nil)
        policyCache.put(detail, for: 300)

        var controlCount = 0
        let totalUsers = 10_000
        for i in 0..<totalUsers {
            let r = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 300, identifier: "user_\(i)")
            if r.controlGroup { controlCount += 1 }
        }
        let controlPct = Double(controlCount * 100) / Double(totalUsers)
        XCTAssertTrue(controlPct > 45 && controlPct < 55,
                      "Real cached policy should produce ~50% control, was: \(controlPct)%")
    }

    func testGetPolicyVariantFromCacheNullInputs() {
        let r1 = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: nil, identifier: "user123")
        XCTAssertTrue(r1.controlGroup)
        XCTAssertEqual(r1.variantId, "0")

        let r2 = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 100, identifier: nil)
        XCTAssertTrue(r2.controlGroup)
        XCTAssertEqual(r2.variantId, "0")
    }

    // MARK: - Control variant id normalization

    func testMurmurBucket_nullVariantId() {
        let detail = PolicyCache.PolicyDetail(id: 801,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "seed-a",
                                              buckets: [PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 9999, percentage: 100)],
                                              previewUserVariantMap: nil)
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: "any-bucketing-id")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, FlagConstants.Policy.CONTROL_GROUP_VARIANT_ID)
    }

    func testMurmurBucket_emptyVariantId() {
        let detail = PolicyCache.PolicyDetail(id: 802,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "seed-b",
                                              buckets: [PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 9999, percentage: 100)],
                                              previewUserVariantMap: nil)
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: "another-id")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testMurmurBucket_explicitZeroString() {
        let detail = PolicyCache.PolicyDetail(id: 803,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "seed-c",
                                              buckets: [PolicyCache.PolicyBucket(variantId: "0", startRange: 0, endRange: 9999, percentage: 100)],
                                              previewUserVariantMap: nil)
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: "user-z")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testMurmurBucket_treatmentVariantUnchanged() {
        let detail = PolicyCache.PolicyDetail(id: 804,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "seed-d",
                                              buckets: [
                                                PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 1, percentage: 50),
                                                PolicyCache.PolicyBucket(variantId: "7", startRange: 2, endRange: 9999, percentage: 50)
                                              ],
                                              previewUserVariantMap: nil)
        var treatmentId: String?
        for i in 0..<100_000 {
            let id = "probe_\(i)"
            let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: id)
            if !r.controlGroup && r.variantId == "7" {
                treatmentId = id
                break
            }
        }
        XCTAssertNotNil(treatmentId, "expected at least one identifier in treatment range 2–9999")
        let again = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: treatmentId!)
        XCTAssertFalse(again.controlGroup)
        XCTAssertEqual(again.variantId, "7")
    }

    func testMurmurNoMatchingBucket() {
        let detail = PolicyCache.PolicyDetail(id: 805,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "seed-e",
                                              buckets: [PolicyCache.PolicyBucket(variantId: "1", startRange: 10001, endRange: 10002, percentage: 1)],
                                              previewUserVariantMap: nil)
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: "any-user")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testPreviewMap_emptyStringValue() {
        let detail = PolicyCache.PolicyDetail(id: 806,
                                              hashAlgorithmType: HashFactory.AlgorithmType.previewSimpleHash.rawValue,
                                              seed: "pv",
                                              buckets: [],
                                              previewUserVariantMap: ["alice": ""])
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: "alice")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testPreviewMap_explicitZero() {
        let detail = PolicyCache.PolicyDetail(id: 807,
                                              hashAlgorithmType: HashFactory.AlgorithmType.previewSimpleHash.rawValue,
                                              seed: "pv",
                                              buckets: [],
                                              previewUserVariantMap: ["bob": "0"])
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: "bob")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testPreviewMap_treatmentPassthrough() {
        let detail = PolicyCache.PolicyDetail(id: 808,
                                              hashAlgorithmType: HashFactory.AlgorithmType.previewSimpleHash.rawValue,
                                              seed: "pv",
                                              buckets: [],
                                              previewUserVariantMap: ["carol": "9"])
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: detail, identifier: "carol")
        XCTAssertFalse(r.controlGroup)
        XCTAssertEqual(r.variantId, "9")
    }

    func testFromCache_emptyControlBucketNormalizes() {
        let detail = PolicyCache.PolicyDetail(id: 809,
                                              hashAlgorithmType: "MURMUR_HASH",
                                              seed: "seed-f",
                                              buckets: [
                                                PolicyCache.PolicyBucket(variantId: "", startRange: 0, endRange: 4999, percentage: 50),
                                                PolicyCache.PolicyBucket(variantId: "1", startRange: 5000, endRange: 9999, percentage: 50)
                                              ],
                                              previewUserVariantMap: nil)
        policyCache.put(detail, for: 809)
        var controlUser: String?
        for i in 0..<100_000 {
            let id = "cache-probe_\(i)"
            let r = PolicyEvaluator.getPolicyVariantFromCache(policyCache: policyCache, policyId: 809, identifier: id)
            if r.controlGroup {
                controlUser = id
                XCTAssertEqual(r.variantId, "0")
                break
            }
        }
        XCTAssertNotNil(controlUser, "expected at least one user in control bucket 0–4999")
    }

    // MARK: - resolveCohortingNamespace

    func testResolveCohortingNamespaceReturnsNullWhenCohortingTypeAbsent() {
        XCTAssertNil(PolicyEvaluator.resolveCohortingNamespace(params: nil))
        XCTAssertNil(PolicyEvaluator.resolveCohortingNamespace(params: [:]))
        XCTAssertNil(PolicyEvaluator.resolveCohortingNamespace(params: [
            FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE: "loginID"
        ]))
    }

    func testEcidCohortingTypeResolvesToEcidNamespace() {
        XCTAssertEqual(PolicyEvaluator.resolveCohortingNamespace(params: [
            FlagConstants.JSONKeys.COHORTING_TYPE: CohortingType.ecid.rawString
        ]), FlagConstants.Policy.DEFAULT_COHORTING_NAMESPACE)
    }

    func testEcidIgnoresNamespaceCode() {
        XCTAssertEqual(PolicyEvaluator.resolveCohortingNamespace(params: [
            FlagConstants.JSONKeys.COHORTING_TYPE: CohortingType.ecid.rawString,
            FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE: "loginID"
        ]), FlagConstants.Policy.DEFAULT_COHORTING_NAMESPACE)
    }

    func testStickyUsesNamespaceCode() {
        XCTAssertEqual(PolicyEvaluator.resolveCohortingNamespace(params: [
            FlagConstants.JSONKeys.COHORTING_TYPE: CohortingType.sticky.rawString,
            FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE: "loginID"
        ]), "loginID")
    }

    func testStickyWithoutNamespaceCodeReturnsNull() {
        XCTAssertNil(PolicyEvaluator.resolveCohortingNamespace(params: [
            FlagConstants.JSONKeys.COHORTING_TYPE: CohortingType.sticky.rawString
        ]))
    }

    func testUnrecognizedCohortingTypeReturnsNull() {
        XCTAssertNil(PolicyEvaluator.resolveCohortingNamespace(params: [
            FlagConstants.JSONKeys.COHORTING_TYPE: "loginID"
        ]))
    }

    // MARK: - getCohortingNamespace on models

    func testFeaturesResponseNoParamsReturnsNull() {
        XCTAssertNil(FeaturesResponse().cohortingNamespace)
    }

    func testFeaturesResponseConsistentAcrossCalls() {
        let featureGroup = FeaturesResponse()
        featureGroup.params = [FlagConstants.JSONKeys.COHORTING_TYPE: "ECID"]
        XCTAssertEqual(featureGroup.cohortingNamespace, featureGroup.cohortingNamespace)
    }

    func testFeatureNoParamsReturnsNull() {
        XCTAssertNil(Feature().cohortingNamespace)
    }

    func testFeatureConsistentAcrossCalls() {
        let feature = Feature()
        feature.params = [FlagConstants.JSONKeys.COHORTING_TYPE: "ECID"]
        XCTAssertEqual(feature.cohortingNamespace, feature.cohortingNamespace)
    }

    // MARK: - getIdentifier identity map

    func testIdentityMapUsedWhenEcidNamespacePresent() {
        let map = IdentityMapTestHelpers.identityMap(namespace: CohortingType.ecid.rawString, id: "from-map")
        XCTAssertEqual(PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: CohortingType.ecid.rawString), "from-map")
    }

    func testPrimaryIdReturnedForMatchingNamespace() {
        let map: [String: [[String: Any]]] = [
            CohortingType.ecid.rawString: [
                IdentityMapTestHelpers.identityEntry(id: "secondary", primary: false),
                IdentityMapTestHelpers.identityEntry(id: "abc123", primary: true)
            ]
        ]
        XCTAssertEqual(PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: CohortingType.ecid.rawString), "abc123")
    }

    func testFallbackToSessionIdWhenIdentityMapNull() {
        let sessionId = PolicyEvaluator.getIdentifier(identityMap: nil, cohortingNamespace: CohortingType.ecid.rawString)
        XCTAssertFalse(sessionId.isEmpty)
        XCTAssertEqual(sessionId, PolicyEvaluator.getIdentifier(identityMap: nil, cohortingNamespace: CohortingType.ecid.rawString))
    }

    func testFallbackToSessionIdWhenNamespaceAbsent() {
        let map = IdentityMapTestHelpers.identityMap(namespace: CohortingType.ecid.rawString, id: "ignored")
        let sessionId = PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: CohortingType.sticky.rawString)
        XCTAssertEqual(sessionId, PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: CohortingType.sticky.rawString))
    }

    func testStickyNamespaceReturnsStickyId() {
        let map = IdentityMapTestHelpers.identityMap(namespace: CohortingType.sticky.rawString, id: "sticky-bucket-id")
        XCTAssertEqual(PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: CohortingType.sticky.rawString), "sticky-bucket-id")
    }

    func testFirstEntryWhenNoPrimary() {
        let map: [String: [[String: Any]]] = [
            CohortingType.ecid.rawString: [IdentityMapTestHelpers.identityEntry(id: "first-id", primary: false)]
        ]
        XCTAssertEqual(PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: CohortingType.ecid.rawString), "first-id")
    }

    func testFallbackToSessionIdWhenIdentityMapEmpty() {
        let sessionId = PolicyEvaluator.getIdentifier(identityMap: [:], cohortingNamespace: CohortingType.ecid.rawString)
        XCTAssertFalse(sessionId.isEmpty)
        XCTAssertEqual(sessionId, PolicyEvaluator.getIdentifier(identityMap: [:], cohortingNamespace: CohortingType.ecid.rawString))
    }

    func testFallbackToSessionIdWhenNamespaceNull() {
        let map = IdentityMapTestHelpers.identityMap(namespace: CohortingType.ecid.rawString, id: "ignored")
        let sessionId = PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: nil)
        XCTAssertFalse(sessionId.isEmpty)
        XCTAssertEqual(sessionId, PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: nil))
        XCTAssertNotEqual(sessionId, "ignored")
    }

    func testFallbackToSessionIdWhenIdMissing() {
        let expectedSessionId = PolicyEvaluator.getIdentifier(identityMap: nil, cohortingNamespace: CohortingType.ecid.rawString)
        let nullIdMap: [String: [[String: Any]]] = [
            CohortingType.ecid.rawString: [IdentityMapTestHelpers.identityEntry(id: nil, primary: true)]
        ]
        XCTAssertEqual(PolicyEvaluator.getIdentifier(identityMap: nullIdMap, cohortingNamespace: CohortingType.ecid.rawString), expectedSessionId)

        let emptyIdMap: [String: [[String: Any]]] = [
            CohortingType.ecid.rawString: [IdentityMapTestHelpers.identityEntry(id: "", primary: true)]
        ]
        XCTAssertEqual(PolicyEvaluator.getIdentifier(identityMap: emptyIdMap, cohortingNamespace: CohortingType.ecid.rawString), expectedSessionId)
    }

    func testCustomNamespaceCodeReturnsMatchingId() {
        let map = IdentityMapTestHelpers.identityMap(namespace: "loginID", id: "login-bucket-id")
        XCTAssertEqual(PolicyEvaluator.getIdentifier(identityMap: map, cohortingNamespace: "loginID"), "login-bucket-id")
    }
}
