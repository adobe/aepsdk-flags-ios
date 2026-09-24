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

/// MurmurHash-backed `HashStrategy`.
/// Uses the same byte-exact MurmurHash core as `MurmurHash.hash(_:)`, but:
///  - the seed is **concatenated** onto the identifier to form the hash input;
///  - the initial digest value is the constant `R = 31`.
struct MurmurHashStrategy: HashStrategy {

    private static let initial: Int32 = 31

    let multiplier: Int = 100

    func hash(identifier: String?, seed: String?) -> Int {
        guard let identifier = identifier, !identifier.isEmpty else { return 0 }
        let input = seed.map { identifier + $0 } ?? identifier
        return Int(MurmurHash.murmur(bytes: Array(input.utf8), initial: Self.initial))
    }
}
