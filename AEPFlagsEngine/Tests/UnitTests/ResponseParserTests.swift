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

final class ResponseParserTests: XCTestCase {

    private func parse(_ body: String) throws -> FGXResponse {
        try ResponseParser.parseFGXResponse(body)
    }

    private func parseFeatureGroups(_ body: String) throws -> [FeaturesResponse] {
        try parse(body).featureGroups
    }

    // MARK: - parseFGXResponse

    func testFeatureGroupWithFeatureObjects() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "flags_variant_feature_group",
                                                 "\"features\":[{"
                                                     + "\"id\":177024,"
                                                     + "\"key\":\"flag_for_variant1_feature_group\","
                                                     + "\"cohortingType\":\"ECID\","
                                                     + "\"policyId\":203264,"
                                                     + "\"hash\":\"1778522135000\""
                                                     + "}]"))

        let fgx = try parse(json)

        XCTAssertEqual(fgx.pollInterval, 120)
        XCTAssertEqual(fgx.contextVersion, FeaturesResponseJsonFixtures.defaultContextVersion)
        XCTAssertEqual(fgx.featureGroups.count, 1)
        XCTAssertEqual(fgx.featureGroups[0].featureGroupId, 23261)
        XCTAssertEqual(fgx.featureGroups[0].featureGroupName, "flags_variant_feature_group")

        let f = fgx.featureGroups[0].featuresObj![0]
        XCTAssertEqual(f.id, 177024)
        XCTAssertEqual(f.feature, "flag_for_variant1_feature_group")
        XCTAssertEqual(f.policyId, 203264)
        XCTAssertEqual(f.featureHash, "1778522135000")
        XCTAssertEqual(f.cohortingNamespace, FlagConstants.Policy.DEFAULT_COHORTING_NAMESPACE)
    }

    func testContextsParsedIntoMetadataMaps() throws {
        let contexts = "["
            + "{\"id\":\"imsOrg\",\"type\":\"STRING\"},"
            + "{\"id\":\"region\",\"type\":\"STRING\"},"
            + "{\"id\":\"userCount\",\"type\":\"INTEGER\"}"
            + "]"
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "rel", "\"features\":[]"),
            contextVersion: "ctx-abc",
            contexts: contexts)

        let fgx = try parse(json)

        XCTAssertEqual(fgx.contextVersion, "ctx-abc")
        XCTAssertEqual(fgx.contextVariableMap["IMSORG"], "imsOrg")
        XCTAssertEqual(fgx.contextVariableMap["REGION"], "region")
        XCTAssertEqual(fgx.fieldDataTypeCache["imsOrg"], "STRING")
        XCTAssertEqual(fgx.fieldDataTypeCache["userCount"], "INTEGER")
    }

    func testComplexContextTypeMappedToString() throws {
        let contexts = "[{\"id\":\"tags\",\"type\":\"COMPLEX\"}]"
        let json = FeaturesResponseJsonFixtures.bodyWithTtlOnly(120, contexts: contexts)
        let fgx = try parse(json)
        XCTAssertEqual(fgx.fieldDataTypeCache["tags"], "STRING")
    }

    func testCriteriaAsObject() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(-1, "standalone_features",
                                                 "\"criteria\":{\"operator\":\"IN\",\"attr\":\"country\"},"
                                                     + "\"features\":[]"))

        let result = try parseFeatureGroups(json)
        XCTAssertNotNil(result[0].criteria)
        XCTAssertTrue(result[0].criteria!.contains("\"operator\""))
    }

    func testFeatureCriteriaAsObject() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(-1, "standalone_features",
                                                 "\"features\":[{"
                                                     + "\"id\":1,"
                                                     + "\"key\":\"ctx-feat\","
                                                     + "\"criteria\":{\"and\":[{\"operator\":\"EQ\",\"attr\":\"locale\",\"val\":\"en_EU\"}]},"
                                                     + "\"hash\":\"1776786530000\""
                                                     + "}]"))

        let criteria = try parseFeatureGroups(json)[0].featuresObj![0].criteria
        XCTAssertNotNil(criteria)
        XCTAssertTrue(criteria!.contains("\"and\""))
    }

    func testNullCriteria() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "flags_variant_feature_group",
                                                 "\"features\":[]"))

        let result = try parseFeatureGroups(json)
        XCTAssertNil(result[0].criteria)
    }

    func testMultipleFeatureGroups() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "first", "\"features\":[]")
                + ","
                + FeaturesResponseJsonFixtures.featureGroup(23262, "second_featureGroup", "\"features\":[]")
                + ","
                + FeaturesResponseJsonFixtures.featureGroup(23263, "third_featureGroup", "\"features\":[]"))

        let result = try parseFeatureGroups(json)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[1].featureGroupId, 23262)
        XCTAssertEqual(result[1].featureGroupName, "second_featureGroup")
    }

    func testMissingFeatureGroupsKey() throws {
        let json = "{\"v\":2,\"ttl\":120,\"contextVersion\":\"v1\",\"contexts\":[]}"
        let fgx = try parse(json)
        XCTAssertEqual(fgx.featureGroups.count, 0)
        XCTAssertEqual(fgx.pollInterval, 120)
    }

    func testPositiveTtlParsedAsPollInterval() throws {
        let fgx = try parse(FeaturesResponseJsonFixtures.bodyWithTtlOnly(90))
        XCTAssertEqual(fgx.pollInterval, 90)
    }

    func testZeroTtlYieldsNullPollInterval() throws {
        let fgx = try parse(FeaturesResponseJsonFixtures.bodyWithTtlOnly(0))
        XCTAssertNil(fgx.pollInterval)
    }

    func testNegativeTtlYieldsNullPollInterval() throws {
        let fgx = try parse(FeaturesResponseJsonFixtures.bodyWithTtlOnly(-30))
        XCTAssertNil(fgx.pollInterval)
    }

    func testMalformedJson() throws {
        XCTAssertThrowsError(try parse("not json at all")) { error in
            XCTAssertTrue(error is ResponseParseException)
        }
    }

    func testEmptyFeatureGroupsArray() throws {
        let json = "{\"v\":2,\"ttl\":90,\"contextVersion\":\"ctx-v1\",\"contexts\":[],\"featureGroups\":[]}"
        let fgx = try parse(json)
        XCTAssertEqual(fgx.version, 2)
        XCTAssertEqual(fgx.contextVersion, "ctx-v1")
        XCTAssertEqual(fgx.featureGroups.count, 0)
        XCTAssertTrue(fgx.contextVariableMap.isEmpty)
    }

    func testFeatureGroupLevelPolicy() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "flags_variant_feature_group",
                                                 "\"policyId\":200372,"
                                                     + "\"policy\":{"
                                                     + "\"seed\":\"1778520509074-seed\","
                                                     + "\"hashAlgorithm\":\"MURMUR_HASH\","
                                                     + "\"buckets\":[{\"start\":0,\"end\":4999,\"variantId\":\"10289730\"}]"
                                                     + "},"
                                                     + "\"features\":[],"
                                                     + "\"hash\":\"1778522135000\""))

        let result = try parseFeatureGroups(json)
        XCTAssertEqual(result[0].policyId, 200372)
        XCTAssertNotNil(result[0].policy)
        XCTAssertEqual(result[0].policy?.hashAlgorithmType, "MURMUR_HASH")
        XCTAssertEqual(result[0].policy?.buckets.count, 1)
        XCTAssertEqual(result[0].policy?.buckets[0].variantId, "10289730")
    }

    func testFeatureGroupCohortingTypePopulatesParams() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(1, "rel", "\"cohortingType\":\"ECID\",\"features\":[]"))
        let featureGroup = try parseFeatureGroups(json)[0]
        XCTAssertEqual(featureGroup.cohortingNamespace, FlagConstants.Policy.DEFAULT_COHORTING_NAMESPACE)
    }

    // MARK: - Policy JSON — variantId edge cases + PolicyEvaluator normalization

    func testOmittedVariantIdInBucket_previewPath() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "flags_variant_feature_group",
                                                 "\"features\":[{"
                                                     + "\"id\":177024,"
                                                     + "\"key\":\"flag_for_variant1_feature_group\","
                                                     + "\"policyId\":500,"
                                                     + "\"policy\":{"
                                                     + "\"hashAlgorithm\":\"PREVIEW_SIMPLE_HASH\",\"seed\":\"x\","
                                                     + "\"buckets\":[{\"start\":0,\"end\":9999}],"
                                                     + "\"previewUserVariantMap\":{\"u1\":\"\"}"
                                                     + "}"
                                                     + "}]"))

        let policy = try parseFeatureGroups(json)[0].featuresObj![0].policy!
        XCTAssertEqual(policy.buckets[0].variantId, "")

        let r = PolicyEvaluator.getPolicyVariant(policyDetail: policy, identifier: "u1")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testNullVariantIdInBucket_parsesAsEmptyString() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "flags_variant_feature_group",
                                                 "\"features\":[{"
                                                     + "\"id\":177026,"
                                                     + "\"key\":\"flag_for_variant2_feature_group\","
                                                     + "\"policyId\":501,"
                                                     + "\"policy\":{"
                                                     + "\"hashAlgorithm\":\"PREVIEW_SIMPLE_HASH\",\"seed\":\"x\","
                                                     + "\"buckets\":[{\"variantId\":null,\"start\":0,\"end\":1}],"
                                                     + "\"previewUserVariantMap\":{\"u2\":\"\"}"
                                                     + "}"
                                                     + "}]"))

        let policy = try parseFeatureGroups(json)[0].featuresObj![0].policy!
        XCTAssertEqual(policy.buckets[0].variantId, "")
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: policy, identifier: "u2")
        XCTAssertEqual(r.variantId, "0")
        XCTAssertTrue(r.controlGroup)
    }

    func testNumericVariantIdZero() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(-1, "standalone_features",
                                                 "\"features\":[{"
                                                     + "\"id\":165494,"
                                                     + "\"key\":\"context_with_10_percentage_ff\","
                                                     + "\"policyId\":502,"
                                                     + "\"policy\":{"
                                                     + "\"hashAlgorithm\":\"MURMUR_HASH\",\"seed\":\"seed-z\","
                                                     + "\"buckets\":[{\"variantId\":0,\"start\":0,\"end\":9999}]"
                                                     + "}"
                                                     + "}]"))

        let policy = try parseFeatureGroups(json)[0].featuresObj![0].policy!
        XCTAssertEqual(policy.buckets[0].variantId, "0")

        let r = PolicyEvaluator.getPolicyVariant(policyDetail: policy, identifier: "any-user")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testStringVariantIdZeroInJson() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(-1, "standalone_features",
                                                 "\"features\":[{"
                                                     + "\"id\":165492,"
                                                     + "\"key\":\"context_with_50_percentage_ff\","
                                                     + "\"policyId\":503,"
                                                     + "\"policy\":{"
                                                     + "\"hashAlgorithm\":\"MURMUR_HASH\",\"seed\":\"seed-w\","
                                                     + "\"buckets\":[{\"variantId\":\"0\",\"start\":0,\"end\":9999}]"
                                                     + "}"
                                                     + "}]"))

        let policy = try parseFeatureGroups(json)[0].featuresObj![0].policy!
        let r = PolicyEvaluator.getPolicyVariant(policyDetail: policy, identifier: "bucketing-user")
        XCTAssertTrue(r.controlGroup)
        XCTAssertEqual(r.variantId, "0")
    }

    func testCdnControlBucketEmptyVariantId() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(-1, "standalone_features",
                                                 "\"features\":[{"
                                                     + "\"id\":165494,"
                                                     + "\"key\":\"context_with_10_percentage_ff\","
                                                     + "\"policyId\":187764,"
                                                     + "\"policy\":{"
                                                     + "\"seed\":\"1776701036230-abadaa27\","
                                                     + "\"hashAlgorithm\":\"MURMUR_HASH\","
                                                     + "\"buckets\":["
                                                     + "{\"start\":0,\"end\":999,\"variantId\":\"10269886\"},"
                                                     + "{\"start\":1000,\"end\":9999,\"variantId\":\"\"}"
                                                     + "]"
                                                     + "}"
                                                     + "}]"))

        let policy = try parseFeatureGroups(json)[0].featuresObj![0].policy!
        XCTAssertEqual(policy.buckets[1].variantId, "")
        XCTAssertEqual(policy.buckets.count, 2)
    }

    func testSkipIncompleteContextEntries() throws {
        let contexts = "["
            + "{\"id\":\"valid\",\"type\":\"STRING\"},"
            + "{\"id\":\"no-type\"},"
            + "{\"type\":\"STRING\"},"
            + "{\"other\":\"stuff\"}"
            + "]"
        let json = FeaturesResponseJsonFixtures.bodyWithTtlOnly(120, contexts: contexts)
        let fgx = try parse(json)
        XCTAssertEqual(fgx.contextVariableMap.count, 1)
        XCTAssertEqual(fgx.fieldDataTypeCache.count, 1)
    }

    func testContextWireTypeStringNormalized() throws {
        let contexts = "[{\"id\":\"appVersion\",\"type\":\"String\"},{\"id\":\"quantity\",\"type\":\"INTEGER\"}]"
        let fgx = try parse(FeaturesResponseJsonFixtures.bodyWithTtlOnly(120, contexts: contexts))
        XCTAssertEqual(fgx.fieldDataTypeCache["appVersion"], "STRING")
        XCTAssertEqual(fgx.fieldDataTypeCache["quantity"], "INTEGER")
        XCTAssertEqual(fgx.contextVariableMap["APPVERSION"], "appVersion")
    }

    func testMalformedPolicyDetailReturnsNil() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "g", ""
                + "\"features\":[{"
                + "\"id\":1,"
                + "\"key\":\"f\","
                + "\"policyId\":500,"
                + "\"policy\":{"
                + "\"id\":500,"
                + "\"hashAlgorithm\":\"MURMUR_HASH\","
                + "\"seed\":\"seed-1\","
                + "\"buckets\":[{\"variantId\":\"9\",\"start\":\"bad\",\"end\":9999,\"percentage\":100}]"
                + "}"
                + "}]"))

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertNil(feature.policy)
    }

    func testFeatureMetaDecodedFromBase64() throws {
        let metaPayload = "{\"buttonColor\":\"#FF6B35\",\"layout\":\"compact\"}"
        let metaBase64 = Data(metaPayload.utf8).base64EncodedString()
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "checkout_redesign_rollout",
                "\"features\":[\(FeaturesResponseJsonFixtures.featureObject(id: 177024, key: "new_checkout_flow", metaBase64: metaBase64))]"
            ))

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertEqual(feature.meta, metaPayload)
        XCTAssertTrue(feature.analyticsEnabled)
    }

    func testFeatureMetaDecodedAsPlainString() throws {
        let metaBase64 = "c2l4X2NvbnRleHRfZmY="
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(23261, "flags_variant_feature_group",
                "\"features\":[\(FeaturesResponseJsonFixtures.featureObject(id: 162888, key: "six_context_ff", metaBase64: metaBase64))]"
            ))

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertEqual(feature.meta, "six_context_ff")
    }

    func testCriteriaAsEscapedJsonString() throws {
        let criteria = #""{\"criteria\":{\"and\":[{\"operator\":\"EQ\",\"attr\":\"PLATFORM\",\"val\":\"WEB\"}]}}""#
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            FeaturesResponseJsonFixtures.featureGroup(1, "group_a",
                "\"criteria\":\(criteria),\"features\":[]"))

        XCTAssertNotNil(try parseFeatureGroups(json)[0].criteria)
        XCTAssertTrue(try parseFeatureGroups(json)[0].criteria!.contains("PLATFORM"))
    }

    func testMinimalBodyParsesRootFields() throws {
        let fgx = try parse(FeaturesResponseJsonFixtures.minimalFGXBody())
        XCTAssertEqual(fgx.version, 2)
        XCTAssertEqual(fgx.pollInterval, 120)
        XCTAssertEqual(fgx.contextVersion, "test-context-v1")
        XCTAssertEqual(fgx.featureGroups.count, 1)
        XCTAssertEqual(fgx.featureGroups[0].featureGroupId, 1001)
        XCTAssertEqual(fgx.featureGroups[0].featureGroupName, "default_feature_group")

        let feature = fgx.featureGroups[0].featuresObj![0]
        XCTAssertEqual(feature.id, 1001)
        XCTAssertEqual(feature.feature, "my-feature")
        XCTAssertEqual(feature.cohortingNamespace, FlagConstants.Policy.DEFAULT_COHORTING_NAMESPACE)
        XCTAssertTrue(feature.analyticsEnabled)
    }

    func testParsesCohortingNamespaceCodeFromParams() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1002, "ns_group",
                "\"features\":[{"
                    + "\"id\":1002,"
                    + "\"key\":\"login-feature\","
                    + "\"params\":{"
                    + "\"cohortingType\":\"STICKY\","
                    + "\"cohortingNamespaceCode\":\"loginID\""
                    + "}"
                    + "}]"),
            contextVersion: "ctx-v1",
            contexts: "[]")

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertEqual(feature.params?[FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE] as? String, "loginID")
        XCTAssertEqual(feature.params?[FlagConstants.JSONKeys.COHORTING_TYPE] as? String, "STICKY")
        XCTAssertEqual(feature.cohortingNamespace, "loginID")
    }

    func testEcidCohortingTypeIgnoresMismatchedNamespaceCode() throws {
        let featureJson = FeaturesResponseJsonFixtures.feature(
            1003, "mixed-feature",
            "\"cohortingType\":\"ECID\",\"cohortingNamespaceCode\":\"loginID\"")
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1003, "mixed_group", "\"features\":[\(featureJson)]"),
            contextVersion: "ctx-v1",
            contexts: "[]")

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertEqual(feature.params?[FlagConstants.JSONKeys.COHORTING_TYPE] as? String, "ECID")
        XCTAssertEqual(feature.params?[FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE] as? String, "loginID")
        XCTAssertEqual(feature.cohortingNamespace, FlagConstants.Policy.DEFAULT_COHORTING_NAMESPACE)
    }

    func testParsesTopLevelCohortingNamespaceCode() throws {
        let featureJson = FeaturesResponseJsonFixtures.feature(
            1004, "top-level-feature",
            "\"cohortingType\":\"STICKY\",\"cohortingNamespaceCode\":\"loginID\"")
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1004, "top_level_group", "\"features\":[\(featureJson)]"),
            contextVersion: "ctx-v1",
            contexts: "[]")

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertEqual(feature.params?[FlagConstants.JSONKeys.COHORTING_TYPE] as? String, "STICKY")
        XCTAssertEqual(feature.params?[FlagConstants.JSONKeys.COHORTING_NAMESPACE_CODE] as? String, "loginID")
    }

    func testAbsentContextsKeyYieldsEmptyMaps() throws {
        let json = FeaturesResponseJsonFixtures.bodyFeaturesOnly(
            120, "ctx-v1",
            FeaturesResponseJsonFixtures.featureGroup(1, "g",
                "\"features\":[\(FeaturesResponseJsonFixtures.feature(1, "f", ""))]"))

        let fgx = try parse(json)
        XCTAssertTrue(fgx.contextVariableMap.isEmpty)
        XCTAssertTrue(fgx.fieldDataTypeCache.isEmpty)
        XCTAssertEqual(fgx.contextVersion, "ctx-v1")
        XCTAssertEqual(fgx.featureGroups.count, 1)
    }

    func testAbsentVersionDefaultsToZero() throws {
        let json = "{\"ttl\":90,\"featureGroups\":[]}"
        let fgx = try parse(json)
        XCTAssertEqual(fgx.version, 0)
    }

    func testFieldDataTypeCachePreservesWireCasing() throws {
        let contexts = "[{\"id\":\"country\",\"type\":\"STRING\"},{\"id\":\"imsOrg\",\"type\":\"STRING\"}]"
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "g",
                "\"features\":[\(FeaturesResponseJsonFixtures.feature(1, "f", ""))]"),
            contextVersion: "ctx-v1",
            contexts: contexts)

        let types = try parse(json).fieldDataTypeCache
        XCTAssertEqual(types["country"], "STRING")
        XCTAssertEqual(types["imsOrg"], "STRING")
        XCTAssertNil(types["COUNTRY"])
    }

    func testIgnoresStringPrimitivesInFeaturesArray() throws {
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            "{\"id\":1,\"key\":\"g\",\"features\":[\"legacy-name\","
                + FeaturesResponseJsonFixtures.feature(2, "object-feature", "") + "]}",
            contextVersion: "ctx-v1",
            contexts: "[]")

        let group = try parseFeatureGroups(json)[0]
        XCTAssertEqual(group.featuresObj?.count, 1)
        XCTAssertEqual(group.featuresObj?[0].feature, "object-feature")
        XCTAssertEqual(group.features, ["object-feature"])
    }

    func testAnalyticsEnabledExplicitFalse() throws {
        let featureJson = FeaturesResponseJsonFixtures.feature(1, "f", "\"analyticsEnabled\":false")
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "g", "\"features\":[\(featureJson)]"),
            contextVersion: "ctx-v1",
            contexts: "[]")

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertFalse(feature.analyticsEnabled)
    }

    func testInvalidBase64MetaYieldsNil() throws {
        let featureJson = FeaturesResponseJsonFixtures.feature(1, "f", "\"meta\":\"!!!not-base64!!!\"")
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "g", "\"features\":[\(featureJson)]"),
            contextVersion: "ctx-v1",
            contexts: "[]")

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertNil(feature.meta)
    }

    func testEmptyDecodedMetaYieldsNil() throws {
        let wire = Data().base64EncodedString()
        let featureJson = FeaturesResponseJsonFixtures.feature(1, "f", "\"meta\":\"\(wire)\"")
        let json = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "g", "\"features\":[\(featureJson)]"),
            contextVersion: "ctx-v1",
            contexts: "[]")

        let feature = try parseFeatureGroups(json)[0].featuresObj![0]
        XCTAssertNil(feature.meta)
    }

    func testBooleanVariantIdCoercesToString() throws {
        let trueJson = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "g",
                "\"features\":[{"
                    + "\"id\":1,\"key\":\"f\",\"policyId\":501,"
                    + "\"policy\":{\"id\":501,\"buckets\":[{\"variantId\":true,\"start\":0,\"end\":9999,\"percentage\":100}]}"
                    + "}]"),
            contextVersion: "ctx-v1",
            contexts: "[]")
        let falseJson = FeaturesResponseJsonFixtures.bodyWithFeatureGroups(
            120,
            FeaturesResponseJsonFixtures.featureGroup(1, "g",
                "\"features\":[{"
                    + "\"id\":1,\"key\":\"f\",\"policyId\":502,"
                    + "\"policy\":{\"id\":502,\"buckets\":[{\"variantId\":false,\"start\":0,\"end\":9999,\"percentage\":100}]}"
                    + "}]"),
            contextVersion: "ctx-v1",
            contexts: "[]")

        XCTAssertEqual(try parseFeatureGroups(trueJson)[0].featuresObj![0].policy?.buckets[0].variantId, "true")
        XCTAssertEqual(try parseFeatureGroups(falseJson)[0].featuresObj![0].policy?.buckets[0].variantId, "false")
    }
}
