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

@testable import AEPFlags
import Foundation

/// `FlagClientManager.InitScheduler` that runs each scheduled block on its own brand-new
/// OS thread instead of a GCD-pooled queue. Tests that need to hold `startAsyncInitialization`
/// "in flight" (e.g. via a `DispatchSemaphore` gate) should inject this instead of relying on
/// the production `DispatchQueue`-backed default: blocking a dedicated thread here cannot starve
/// GCD's shared `.utility` worker pool the way blocking a real pooled queue can, which is what
/// made the equivalent tests flaky on constrained CI runners.
final class DedicatedThreadInitScheduler: FlagClientManager.InitScheduler {
    func schedule(_ work: @escaping () -> Void) {
        Thread.detachNewThread(work)
    }
}
