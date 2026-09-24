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

/// Never-matching filter used when criteria JSON cannot be parsed on the evaluation
/// path so that invalid criteria fail closed.
struct RejectingFilter: IFilter {

    func isValid(_ userAttributes: UserAttributes) -> Bool {
        return false
    }

    func validateWithReturnValues(_ userAttributes: UserAttributes) -> FilterResult {
        return FilterResult(isValid: false, matchedAttributes: UserAttributes())
    }
}
