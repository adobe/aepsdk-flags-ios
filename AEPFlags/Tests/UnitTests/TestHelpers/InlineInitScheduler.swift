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

/// `FlagClientManager.InitScheduler` that runs the scheduled block immediately on the calling thread.
///
/// Tests that only care about the *outcome* of client creation (ready, failed) use this so the create
/// step does not depend on when the OS gets around to running a low-priority background queue.
/// State changes after creation still hop through the manager's own serial state queue, so the
/// asynchronous contract of `startAsyncInitialization` (resolver invoked after the call returns)
/// is preserved. Do not use it together with a blocking `createOverride`; use
/// `DedicatedThreadInitScheduler` for that.
final class InlineInitScheduler: FlagClientManager.InitScheduler {
    func schedule(_ work: @escaping () -> Void) {
        work()
    }
}
