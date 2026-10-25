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

/// `FlagClientManager.InitScheduler` that runs each scheduled block on its own new OS thread.
///
/// Tests that hold client creation "in flight" (for example with a `DispatchSemaphore` gate) use this,
/// so the held work never blocks the test thread or another test's queue.
final class DedicatedThreadInitScheduler: FlagClientManager.InitScheduler {
    func schedule(_ work: @escaping () -> Void) {
        Thread.detachNewThread(work)
    }
}
