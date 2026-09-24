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

/// Common protocol for every filter node — leaf filters (`Filter`), composite
/// expressions (`FilterExpression`), and sentinels (`EmptyFilter`, `RejectingFilter`).
protocol IFilter {

    /// `true` if `userAttributes` satisfies the filter.
    func isValid(_ userAttributes: UserAttributes) -> Bool

    /// Validate and return the matched attribute keys alongside the result.
    func validateWithReturnValues(_ userAttributes: UserAttributes) -> FilterResult
}

/// Result of `IFilter.validateWithReturnValues(_:)`.
/// Top-level type because Swift protocols cannot host nested types.
struct FilterResult {

    let isValid: Bool
    let matchedAttributes: UserAttributes

    init(isValid: Bool, matchedAttributes: UserAttributes?) {
        self.isValid = isValid
        self.matchedAttributes = matchedAttributes ?? UserAttributes()
    }
}
