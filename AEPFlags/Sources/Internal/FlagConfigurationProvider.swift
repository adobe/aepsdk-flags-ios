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

@_implementationOnly import FlagsEngine
import AEPServices
import Foundation

enum FlagConfigurationProvider {
    private static let selfTag = "FlagConfigurationProvider"

    static func buildConfiguration(_ configData: [String: Any]) -> FlagsSDKConfiguration? {
        do {
            let edgeDomain = resolveEdgeDomain(configData)

            let imsOrg = FlagDataReader.optString(configData, key: FlagConstants.Configuration.experienceCloudOrg)
            let sandbox = FlagDataReader.optString(configData, key: FlagConstants.Configuration.flagsSandbox)
            let clientId = FlagDataReader.optString(configData, key: FlagConstants.Configuration.flagsClientId)

            if isNullOrEmpty(imsOrg) || isNullOrEmpty(sandbox) || isNullOrEmpty(clientId) {
                Log.debug(
                    label: FlagConstants.logTag,
                    "\(selfTag) - buildConfiguration - Missing required config (imsOrg=\(!isNullOrEmpty(imsOrg)), sandbox=\(!isNullOrEmpty(sandbox)), clientId=\(!isNullOrEmpty(clientId)))."
                )
                return nil
            }

            return try FlagsSDKConfiguration.builder()
                .edgeDomain(edgeDomain)
                .imsOrg(imsOrg!)
                .sandboxName(sandbox!)
                .clientId(clientId!)
                .sdkVersion(FlagConstants.extensionVersion)
                .build()
        } catch {
            Log.warning(
                label: FlagConstants.logTag,
                "\(selfTag) - buildConfiguration - Failed to build configuration: \(error.localizedDescription)"
            )
            return nil
        }
    }

    /// Resolves the configured service domain, falling back to the default when the configured value
    /// is missing or blank.
    static func resolveEdgeDomain(_ configData: [String: Any]) -> String {
        guard let configuredDomain = FlagDataReader.optString(configData, key: FlagConstants.Configuration.edgeDomain) else {
            Log.debug(
                label: FlagConstants.logTag,
                "\(selfTag) - resolveEdgeDomain - edge.domain is missing; using default domain \(FlagConstants.Configuration.defaultEdgeDomain)."
            )
            return FlagConstants.Configuration.defaultEdgeDomain
        }

        let trimmedDomain = configuredDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDomain.isEmpty {
            Log.debug(
                label: FlagConstants.logTag,
                "\(selfTag) - resolveEdgeDomain - edge.domain is blank; using default domain \(FlagConstants.Configuration.defaultEdgeDomain)."
            )
            return FlagConstants.Configuration.defaultEdgeDomain
        }

        return trimmedDomain
    }

    static func hasRequiredConfig(_ configData: [String: Any]) -> Bool {
        let imsOrg = FlagDataReader.optString(configData, key: FlagConstants.Configuration.experienceCloudOrg)
        let sandbox = FlagDataReader.optString(configData, key: FlagConstants.Configuration.flagsSandbox)
        let clientId = FlagDataReader.optString(configData, key: FlagConstants.Configuration.flagsClientId)
        return !isNullOrEmpty(imsOrg) && !isNullOrEmpty(sandbox) && !isNullOrEmpty(clientId)
    }

    private static func isNullOrEmpty(_ value: String?) -> Bool {
        value == nil || value?.isEmpty == true
    }
}
