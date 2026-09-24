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

#if canImport(UIKit)
import UIKit

/// Forwards process-level `UIApplication` background / foreground notifications to ``Flag/setAppState(_:)``.
/// Binds UIKit application lifecycle notifications to
/// ``setAppState(_:)`` — the SDK listens to app-wide `UIApplication` notifications (UIKit and
/// typical SwiftUI apps on iPhone / iPad).
/// - Important: Call ``start()`` only after ``Flag`` has finished initializing. If ``setAppState`` fails
///   (e.g. not yet initialized), failures are ignored so startup ordering stays forgiving.
/// - Important: Retain this binding for as long as forwarding should remain active; call ``stop()`` when done.
@objc(AEPMobileFlagApplicationLifecycleBinding)
public final class FlagApplicationLifecycleBinding: NSObject {

    private weak var flag: Flag?
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observerTokens: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - flag: Client to receive ``AppState`` updates.
    ///   - notificationCenter: Center to observe. Use ``NotificationCenter/default`` in production. Tests may inject a dedicated instance and post synthetic notifications there.
    @objc public init(flag: Flag, notificationCenter: NotificationCenter = .default) {
        self.flag = flag
        self.notificationCenter = notificationCenter
        super.init()
    }

    /// Registers `UIApplication.didEnterBackground` / `willEnterForeground` observers. Idempotent.
    @objc public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard observerTokens.isEmpty else { return }

        observerTokens.append(notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forward(.background)
        })

        observerTokens.append(notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forward(.foreground)
        })
    }

    /// Removes notification observers. Safe to call multiple times.
    @objc public func stop() {
        lock.lock()
        let tokens = observerTokens
        observerTokens.removeAll()
        lock.unlock()
        for token in tokens {
            notificationCenter.removeObserver(token)
        }
    }

    private func forward(_ state: AppState) {
        guard let flag = flag else { return }
        do {
            try flag.setAppState(state)
        } catch {
            FlagLog.debug("[Flags] Application lifecycle binding skipped setAppState (\(state)): \(error.localizedDescription)")
        }
    }

    deinit {
        stop()
    }
}
#endif
