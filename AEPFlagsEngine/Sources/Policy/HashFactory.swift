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

/// Factory for `HashStrategy` implementations.
/// Supports `MURMUR_HASH` (production) and
/// `PREVIEW_SIMPLE_HASH` (preview / debugging) algorithms, with MurmurHash as the default.
enum HashFactory {

    /// Hash-algorithm identifier. Wire values are upper-snake-case.
    enum AlgorithmType: String {
        case murmurHash         = "MURMUR_HASH"
        case previewSimpleHash  = "PREVIEW_SIMPLE_HASH"
    }

    /// Thread-safe strategy registry. Reads use the concurrent queue without a barrier;
    /// `register(_:for:)` writes with a barrier to serialize against concurrent reads.
    private static var strategies: [AlgorithmType: HashStrategy] = [
        .murmurHash: MurmurHashStrategy(),
        .previewSimpleHash: SimpleHashStrategy()
    ]
    private static let queue = DispatchQueue(label: "com.adobe.marketing.flags.hashfactory",
                                             attributes: .concurrent)

    /// Strategy for the requested algorithm. Falls back to MurmurHash for unknown types.
    static func strategy(for type: AlgorithmType) -> HashStrategy {
        queue.sync {
            strategies[type] ?? (strategies[.murmurHash] ?? MurmurHashStrategy())
        }
    }

    /// Strategy for the wire string (case-insensitive). Falls back to MurmurHash for unknown / empty input.
    static func strategy(for typeName: String?) -> HashStrategy {
        guard let raw = typeName, !raw.isEmpty,
              let type = AlgorithmType(rawValue: raw.uppercased()) else {
            return strategy(for: .murmurHash)
        }
        return strategy(for: type)
    }

    /// Register a custom strategy. Thread-safe. Blocks until the registration is
    /// visible to subsequent `strategy(for:)` calls.
    static func register(_ strategy: HashStrategy, for type: AlgorithmType) {
        queue.sync(flags: .barrier) {
            strategies[type] = strategy
        }
    }
}

// MARK: - Preview / debug strategy

/// Simple recurrence hash used for previewing rule outcomes during development.
/// Algorithm: `h = (R * h + char) % M` where `R = 31`, `M = 10_000`.
struct SimpleHashStrategy: HashStrategy {

    private static let M: Int = 10_000
    private static let R: Int = 31

    let multiplier: Int = 100

    func hash(identifier: String?, seed: String?) -> Int {
        guard let identifier = identifier, !identifier.isEmpty else { return 0 }
        let input = seed.map { identifier + $0 } ?? identifier

        var h: Int = 0
        for scalar in input.unicodeScalars {
            h = (Self.R &* h &+ Int(scalar.value)) % Self.M
        }
        return h
    }
}
