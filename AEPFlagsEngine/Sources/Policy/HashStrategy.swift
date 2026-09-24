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

/// Hash strategy used by the policy evaluator.
/// Implementations must return a deterministic value in `0...9999`.
/// The `seed` parameter is **concatenated** to `identifier` to form the hash input — it is
/// NOT passed as a hash-algorithm seed.
protocol HashStrategy {

    /// Compute a hash value for the given identifier + policy seed.
    /// - Parameters:
    ///   - identifier: User / visitor identifier.
    ///   - seed: Policy seed string, concatenated to `identifier`. May be nil.
    /// - Returns: Hash value in `0...9999`.
    func hash(identifier: String?, seed: String?) -> Int

    /// Multiplier used when converting a hash value to a bucket index (typically `100`).
    var multiplier: Int { get }
}
