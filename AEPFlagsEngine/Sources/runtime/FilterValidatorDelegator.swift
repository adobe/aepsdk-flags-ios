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

/// Protocol implemented by delegators that drive nested filter validation
/// (e.g. `CONTAINS` over a list of nested `UserAttributes`).
protocol FilterValidatorDelegator {

    /// Run the validation. Returns `true` if at least one nested state passes.
    func delegate(stateValue: Any?,
                  filterValue: Any?,
                  relationalEquality: Any?) -> Bool

    /// Run the validation and report the matched attributes from the first hit.
    func delegateWithReturnValues(stateValue: Any?,
                                  filterValue: Any?,
                                  relationalEquality: Any?,
                                  id: Int,
                                  attrId: String?) -> FilterResult

    /// Run the validation and report all matching nested states.
    func delegateWithAllReturnValues(stateValue: Any?,
                                     filterValue: Any?,
                                     relationalEquality: Any?,
                                     id: Int,
                                     attrId: String?) -> [UserAttributes]

    /// Hook for the caller to add `selected_*` attributes onto each nested state
    /// before validation runs.
    func preprocessUserAttributes(stateValue: Any?, objectToValidate: UserAttributes)
}
