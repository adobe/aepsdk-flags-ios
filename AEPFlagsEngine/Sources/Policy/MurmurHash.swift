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

/// MurmurHash implementation for consistent user bucketing.
/// Used by the policy evaluator for A/B testing — produces a value in `0...9999`.
/// Byte loads use signed sign-extension at block boundaries; arithmetic uses
/// overflow operators (`&*`, `&<<`) for 32-bit digest semantics.
enum MurmurHash {

    /// Domain modulus (hash range = `0..<M`).
    @usableFromInline static let M: Int32 = 10_000
    /// Initial seed value, XORed with the input length to start the digest.
    @usableFromInline static let SEED: Int32 = 31
    /// MurmurHash mix constant.
    @usableFromInline static let MIX: Int32 = 0x5bd1e995
    /// Bucket size multiplier (`hash / multiplier` → bucket index).
    static let multiplier: Int = 100

    /// Compute the MurmurHash of `value`. Returns `0` for nil/empty input.
    static func hash(_ value: String?) -> Int {
        guard let value = value, !value.isEmpty else { return 0 }
        return Int(murmur(bytes: Array(value.utf8), initial: SEED))
    }

    /// Bit-exact core. Shared by `MurmurHash.hash(_:)` and
    /// `MurmurHashStrategy.hash(identifier:seed:)` so both produce identical digests.
    @usableFromInline
    static func murmur(bytes data: [UInt8], initial: Int32) -> Int32 {
        let length = Int32(data.count)
        var h: Int32 = initial ^ length

        let len4 = Int(length >> 2)
        for i in 0..<len4 {
            let base = i << 2
            // Sign-extend the high byte of each 4-byte block
            // then OR in unsigned lower bytes.
            var k: Int32 = Int32(Int8(bitPattern: data[base + 3]))
            k = (k &<< 8) | Int32(data[base + 2])
            k = (k &<< 8) | Int32(data[base + 1])
            k = (k &<< 8) | Int32(data[base + 0])
            k = k &* MIX
            // Unsigned right shift via UInt32 view
            k ^= Int32(bitPattern: UInt32(bitPattern: k) >> 24)
            k = k &* MIX
            h = h &* MIX
            h ^= k
        }

        let consumed = len4 << 2
        let left = Int(length) - consumed
        if left != 0 {
            let last = Int(length)
            if left >= 3 {
                h ^= Int32(Int8(bitPattern: data[last - 3])) &<< 16
            }
            if left >= 2 {
                h ^= Int32(Int8(bitPattern: data[last - 2])) &<< 8
            }
            if left >= 1 {
                h ^= Int32(Int8(bitPattern: data[last - 1]))
            }
            h = h &* MIX
        }

        h ^= Int32(bitPattern: UInt32(bitPattern: h) >> 13)
        h = h &* MIX
        h ^= Int32(bitPattern: UInt32(bitPattern: h) >> 15)

        var result = h % M
        if result < 0 { result = -result }
        return result
    }
}
