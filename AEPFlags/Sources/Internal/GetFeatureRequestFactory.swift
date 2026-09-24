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
import Foundation

/// Builds `GetFeatureRequest` instances for the Flags engine.
enum GetFeatureRequestFactory {
    static func create(
        context: [String: [String]]?,
        identityMap: [String: [[String: Any]]]?
    ) -> FlagsSDKGetFeatureRequest {
        let builder = FlagsSDKGetFeatureRequest.builder()
        if let context {
            builder.context(context)
        }
        if let identityMap, !identityMap.isEmpty {
            builder.identityMap(identityMap)
        }
        return builder.build()
    }
}
