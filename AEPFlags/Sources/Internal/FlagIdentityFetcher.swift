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

import AEPCore
import Foundation

/// Reads the current Edge Identity map for feature evaluation requests.
///
/// Implementations read Edge Identity synchronously from XDM shared state (event-ordered, no
/// blocking callback) and do not maintain a separate identity cache in the Flags extension.
protocol FlagIdentityFetcher {
    /// Returns the current identity map in XDM `identityMap` shape, or `nil` when identities are
    /// unavailable (Edge Identity not registered, shared state pending, or empty).
    func fetchIdentityMap(extensionRuntime: ExtensionRuntime, event: Event) -> [String: [[String: Any]]]?

    /// Returns whether flag API events may be delivered for evaluation.
    ///
    /// When Edge Identity is not registered (no XDM shared state entry), returns `true` so
    /// evaluations without identity remain supported. When Edge Identity is registered, returns
    /// `true` only after its XDM shared state is `.set`.
    func isIdentityReady(extensionRuntime: ExtensionRuntime, event: Event) -> Bool

    /// Optional warm-up hook called once at initialization; default is no-op.
    func warmUp()
}

extension FlagIdentityFetcher {
    func warmUp() {}
}
