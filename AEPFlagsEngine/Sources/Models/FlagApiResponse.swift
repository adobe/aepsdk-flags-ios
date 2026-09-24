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

/// HTTP-aware wrapper around a CDN fetch result. Carries `ETag`, change flag, and the
/// parsed CDN body (`FGXResponse`).
struct FlagApiResponse {

    /// Parsed combined response body; `nil` when absent.
    let fgxResponse: FGXResponse?
    let etag: String?
    let isChanged: Bool

    /// Parsed feature groups; `nil` when `fgxResponse` is absent.
    var featuresResponses: [FeaturesResponse]? { fgxResponse?.featureGroups }

    /// Poll interval from CDN root `ttl`; `nil` when body is absent or `ttl` is non-positive.
    var pollInterval: Int? { fgxResponse?.pollInterval }
}
