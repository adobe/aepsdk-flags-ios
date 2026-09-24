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

@testable import AEPFlags
import FlagsEngine
import XCTest

class FlagConfigurationProviderTests: XCTestCase {

    func testResolveEdgeDomain_configuredValue() {
        let configData: [String: Any] = [
            FlagConstants.Configuration.edgeDomain: "my-company.data.adobedc.net"
        ]
        XCTAssertEqual(
            "my-company.data.adobedc.net",
            FlagConfigurationProvider.resolveEdgeDomain(configData)
        )
    }

    func testResolveEdgeDomain_trimsWhitespace() {
        let configData: [String: Any] = [
            FlagConstants.Configuration.edgeDomain: "  my.domain.com  "
        ]
        XCTAssertEqual("my.domain.com", FlagConfigurationProvider.resolveEdgeDomain(configData))
    }

    func testResolveEdgeDomain_missingKey_usesDefault() {
        XCTAssertEqual(
            FlagConstants.Configuration.defaultEdgeDomain,
            FlagConfigurationProvider.resolveEdgeDomain(createValidConfigData())
        )
    }

    func testResolveEdgeDomain_emptyString_usesDefault() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.edgeDomain] = ""
        XCTAssertEqual(
            FlagConstants.Configuration.defaultEdgeDomain,
            FlagConfigurationProvider.resolveEdgeDomain(configData)
        )
    }

    func testResolveEdgeDomain_whitespaceOnly_usesDefault() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.edgeDomain] = "   "
        XCTAssertEqual(
            FlagConstants.Configuration.defaultEdgeDomain,
            FlagConfigurationProvider.resolveEdgeDomain(configData)
        )
    }

    func testBuildConfiguration_validConfig() throws {
        let config = FlagConfigurationProvider.buildConfiguration(createValidConfigData())
        XCTAssertNotNil(config)
        XCTAssertEqual(FlagConstants.Configuration.defaultEdgeDomain, config?.edgeDomain)
        XCTAssertTrue(config?.clientId.contains("my-app") == true)
    }

    func testBuildConfiguration_missingImsOrg() {
        var configData = createValidConfigData()
        configData.removeValue(forKey: FlagConstants.Configuration.experienceCloudOrg)
        XCTAssertNil(FlagConfigurationProvider.buildConfiguration(configData))
    }

    func testBuildConfiguration_missingSandbox() {
        var configData = createValidConfigData()
        configData.removeValue(forKey: FlagConstants.Configuration.flagsSandbox)
        XCTAssertNil(FlagConfigurationProvider.buildConfiguration(configData))
    }

    func testBuildConfiguration_missingClientId() {
        var configData = createValidConfigData()
        configData.removeValue(forKey: FlagConstants.Configuration.flagsClientId)
        XCTAssertNil(FlagConfigurationProvider.buildConfiguration(configData))
    }

    func testBuildConfiguration_emptyClientId() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.flagsClientId] = ""
        XCTAssertNil(FlagConfigurationProvider.buildConfiguration(configData))
    }

    func testBuildConfiguration_emptyImsOrg() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.experienceCloudOrg] = ""
        XCTAssertNil(FlagConfigurationProvider.buildConfiguration(configData))
    }

    func testBuildConfiguration_emptySandbox() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.flagsSandbox] = ""
        XCTAssertNil(FlagConfigurationProvider.buildConfiguration(configData))
    }

    func testBuildConfiguration_multipleClientIds() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.flagsClientId] = "app1,app2,app3"
        let config = FlagConfigurationProvider.buildConfiguration(configData)
        XCTAssertNotNil(config)
        XCTAssertTrue(config?.clientId.contains("app1") == true)
        XCTAssertTrue(config?.clientId.contains("app2") == true)
        XCTAssertTrue(config?.clientId.contains("app3") == true)
    }

    func testBuildConfiguration_configuredEdgeDomain() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.edgeDomain] = "custom.domain.com"
        let config = FlagConfigurationProvider.buildConfiguration(configData)
        XCTAssertNotNil(config)
        XCTAssertEqual("custom.domain.com", config?.edgeDomain)
    }

    func testBuildConfiguration_defaultEdgeDomainWhenMissing() {
        let config = FlagConfigurationProvider.buildConfiguration(createValidConfigData())
        XCTAssertNotNil(config)
        XCTAssertEqual(FlagConstants.Configuration.defaultEdgeDomain, config?.edgeDomain)
    }

    func testHasRequiredConfig_allPresent() {
        XCTAssertTrue(FlagConfigurationProvider.hasRequiredConfig(createValidConfigData()))
    }

    func testHasRequiredConfig_missingImsOrg() {
        var configData = createValidConfigData()
        configData.removeValue(forKey: FlagConstants.Configuration.experienceCloudOrg)
        XCTAssertFalse(FlagConfigurationProvider.hasRequiredConfig(configData))
    }

    func testHasRequiredConfig_missingSandbox() {
        var configData = createValidConfigData()
        configData.removeValue(forKey: FlagConstants.Configuration.flagsSandbox)
        XCTAssertFalse(FlagConfigurationProvider.hasRequiredConfig(configData))
    }

    func testHasRequiredConfig_missingClientId() {
        var configData = createValidConfigData()
        configData.removeValue(forKey: FlagConstants.Configuration.flagsClientId)
        XCTAssertFalse(FlagConfigurationProvider.hasRequiredConfig(configData))
    }

    func testHasRequiredConfig_emptyValues() {
        var configData = createValidConfigData()
        configData[FlagConstants.Configuration.experienceCloudOrg] = ""
        XCTAssertFalse(FlagConfigurationProvider.hasRequiredConfig(configData))
    }

    private func createValidConfigData() -> [String: Any] {
        [
            FlagConstants.Configuration.experienceCloudOrg: "test@AdobeOrg",
            FlagConstants.Configuration.flagsSandbox: "prod",
            FlagConstants.Configuration.flagsClientId: "my-app"
        ]
    }
}
