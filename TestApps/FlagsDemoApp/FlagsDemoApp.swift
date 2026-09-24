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
import AEPEdgeIdentity
import AEPFlags
import SwiftUI
import UIKit

private enum DemoTheme {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let accent = Color(red: 0.10, green: 0.45, blue: 0.91)
    static let accentLight = Color(red: 0.10, green: 0.45, blue: 0.91).opacity(0.12)
    static let onGreen = Color(red: 0.30, green: 0.69, blue: 0.31)
    static let offGrey = Color(red: 0.74, green: 0.74, blue: 0.74)
    static let errorOrange = Color(red: 1.0, green: 0.60, blue: 0.0)
    static let bodyText = Color(red: 0.22, green: 0.28, blue: 0.31)
    static let border = Color(red: 0.90, green: 0.91, blue: 0.92)
    static let red = Color(red: 0.90, green: 0.22, blue: 0.21)
}

/// App lifecycle state exercised via the demo's lifecycle toggle.
enum AppLifecycleState: String {
    case foreground = "Foreground"
    case background = "Background"
}

/// A single timestamped activity-log line.
struct LogLine: Identifiable {
    let id = UUID()
    let timestamp: String
    let message: String
}

/// Shared, observable test/validation state for the Flags demo.
///
/// Mirrors the Luma Flags reference app's view model: live ECID, an on-screen
/// activity log, app lifecycle toggling, runtime config override, and an optional
/// custom identity injected into the evaluation context.
final class FlagsDemoStore: ObservableObject {
    @Published var ecid: String = FlagDemoFetchConfig.ecidValue
    @Published var logs: [LogLine] = []
    @Published var appState: AppLifecycleState = .foreground

    // Runtime config-override fields (dev/testing only).
    @Published var clientId: String = ""
    @Published var sandbox: String = ""
    @Published var imsOrg: String = ""
    @Published var edgeDomain: String = ""

    // Optional custom identity injected into the evaluation context.
    @Published var useCustomIdentity: Bool = false
    @Published var identityNamespace: String = "ECID"
    @Published var identityId: String = ""

    init() {
        addLog("Flags SDK version: \(Flag.extensionVersion)")
        refreshEcid()
    }

    /// Resolves the current ECID from AEP Edge Identity.
    func refreshEcid() {
        Identity.getExperienceCloudId { [weak self] ecid, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let ecid, !ecid.isEmpty {
                    self.ecid = ecid
                    self.addLog("ECID: \(ecid.prefix(8))…")
                } else if let error {
                    self.addLog("ECID resolution failed: \(error.localizedDescription)")
                } else {
                    self.addLog("ECID not available yet")
                }
            }
        }
    }

    /// Builds the evaluation context from editor entries, adding the custom identity when enabled.
    func buildEvaluationContext(from entries: [ContextEntry]) -> FeatureEvaluationContext {
        FlagDemoFetchConfig.buildEvaluationContext(
            from: entries,
            customIdentityNamespace: useCustomIdentity ? identityNamespace : nil,
            customIdentityId: useCustomIdentity ? identityId : nil
        )
    }

    /// Drives `MobileCore` lifecycle to test polling and cache-refresh behavior.
    func setAppState(_ state: AppLifecycleState) {
        appState = state
        switch state {
        case .foreground:
            MobileCore.lifecycleStart(additionalContextData: nil)
            addLog("FOREGROUND — lifecycleStart, polling resumes")
        case .background:
            MobileCore.lifecyclePause()
            addLog("BACKGROUND — lifecyclePause, polling paused")
        }
    }

    /// Applies a runtime configuration override for any non-empty field.
    ///
    /// Dev/testing only: production apps rely on the Data Collection mobile property.
    func applyConfigOverride() {
        var update: [String: Any] = [:]
        if !clientId.isEmpty { update[FlagDemoFetchConfig.ConfigKeys.clientId] = clientId }
        if !sandbox.isEmpty { update[FlagDemoFetchConfig.ConfigKeys.sandbox] = sandbox }
        if !imsOrg.isEmpty { update[FlagDemoFetchConfig.ConfigKeys.imsOrg] = imsOrg }
        if !edgeDomain.isEmpty { update[FlagDemoFetchConfig.ConfigKeys.edgeDomain] = edgeDomain }

        guard !update.isEmpty else {
            addLog("Config override skipped: all fields empty")
            return
        }
        MobileCore.updateConfigurationWith(configDict: update)
        addLog("Config override applied: \(update.keys.sorted().joined(separator: ", "))")
    }

    func clearLogs() { logs = [] }

    func addLog(_ message: String) {
        // On-screen activity log only — intentionally does not write to the
        // console so the SDK's backend/network logs stay readable there.
        let ts = FlagsDemoStore.timeFormatter.string(from: Date())
        logs = [LogLine(timestamp: ts, message: message)] + logs.prefix(99)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}

@main
struct FlagsDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = FlagsDemoStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                FlagsTestScreen()
                    .tabItem {
                        Label("Flags", systemImage: "list.bullet")
                    }
                GetFeatureScreen()
                    .tabItem {
                        Label("Get Feature", systemImage: "doc.text")
                    }
            }
            .environmentObject(store)
        }
    }
}

/// Flags evaluation demo UI.
struct FlagsTestScreen: View {
    @EnvironmentObject private var store: FlagsDemoStore
    @State private var fetchCount = 0
    @State private var fetchLabel = ""
    @State private var isLoading = false
    @State private var featureStates: [FeatureState] = []
    @State private var contextEntries = FlagDemoFetchConfig.defaultContextEntries

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                statusCard
                IdentitiesCard(ecid: store.ecid) { store.refreshEcid() }
                fetchButton
                if !featureStates.isEmpty {
                    featureResultsSection
                }
                evaluationContextCard
                CustomIdentityCard(store: store)
                LifecycleCard(store: store)
                ConfigOverrideCard(store: store)
                ActivityLogCard(store: store)
                interpretingCard
                Spacer(minLength: 24)
            }
            .padding(16)
        }
        .background(DemoTheme.background.ignoresSafeArea())
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Flags")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(DemoTheme.accent)
            Text(fetchLabel.isEmpty ? "Flags extension  |  v\(Flag.extensionVersion)"
                 : "Flags extension  |  v\(Flag.extensionVersion)  |  \(fetchLabel)")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
    }

    private var statusCard: some View {
        DemoCard {
            HStack(spacing: 8) {
                Circle()
                    .fill(DemoTheme.onGreen)
                    .frame(width: 10, height: 10)
                Text("Flags: ready")
                    .font(.system(size: 14, weight: .medium))
            }
        }
    }

    private var evaluationContextCard: some View {
        DemoCard {
            HStack {
                Text("Evaluation Context")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    contextEntries.append(ContextEntry(key: "", value: ""))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(DemoTheme.accent)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }

            Text("Attributes sent with each flag evaluation request.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .padding(.top, 2)

            VStack(spacing: 8) {
                ForEach($contextEntries) { $entry in
                    HStack(spacing: 8) {
                        TextField("key", text: $entry.key)
                            .font(.system(size: 13))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disableAutocorrection(true)
                        TextField("value", text: $entry.value)
                            .font(.system(size: 13))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                        Button {
                            contextEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DemoTheme.red)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if contextEntries.isEmpty {
                    Text("No attributes yet. Add one above to customize flag evaluation.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8)
        }
    }

    private var interpretingCard: some View {
        DemoCard {
            Text("Interpreting flag results")
                .font(.system(size: 16, weight: .bold))
            Text(
                "Green = Flag.isFeatureEnabled returned true for this ECID + Evaluation Context. " +
                "Grey = returned false under current rules (expected if profile or sandbox does not match provisioned data)."
            )
            .font(.system(size: 13))
            .foregroundColor(DemoTheme.bodyText)
            .padding(.top, 8)
            Text(
                "Orange dot + Error line = SDK callback failed (network, IMS, or server error). Check console logs."
            )
            .font(.system(size: 13))
            .foregroundColor(DemoTheme.bodyText)
            .padding(.top, 8)
            Text(
                "Fetch Features evaluates keys one at a time so the SDK does not hit general.callback.timeout " +
                "from too many parallel requests."
            )
            .font(.system(size: 12))
            .foregroundColor(.gray)
            .padding(.top, 6)
        }
    }

    private var fetchButton: some View {
        Button {
            fetchAllFeaturesSequentially()
        } label: {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("⟳  Fetch Features")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
            }
            .frame(height: 50)
        }
        .buttonStyle(DemoPrimaryButtonStyle())
        .disabled(isLoading)
    }

    private var featureResultsSection: some View {
        let enabledCount = featureStates.filter(\.enabled).count
        let errorCount = featureStates.filter { $0.evaluationError != nil }.count

        return Group {
            Text("Feature Flags (\(enabledCount)/\(featureStates.count) on, \(errorCount) errors)")
                .font(.system(size: 16, weight: .bold))

            DemoCard {
                VStack(spacing: 0) {
                    ForEach(Array(featureStates.enumerated()), id: \.element.id) { index, state in
                        FeatureStateRow(state: state)
                        if index < featureStates.count - 1 {
                            Divider()
                                .background(Color(red: 0.94, green: 0.94, blue: 0.94))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Sequential batch evaluation (avoids parallel callback timeouts).
    private func fetchAllFeaturesSequentially() {
        isLoading = true
        store.addLog("Fetching \(FlagDemoFetchConfig.knownFeatures.count) features via isFeatureEnabled()")
        let evaluationContext = store.buildEvaluationContext(from: contextEntries)
        let features = FlagDemoFetchConfig.knownFeatures
        var results: [FeatureState] = []

        func finishBatch() {
            fetchCount += 1
            fetchLabel = "Fetch #\(fetchCount)"
            featureStates = results.sorted { $0.key < $1.key }
            isLoading = false
            let onCount = results.filter(\.enabled).count
            let errCount = results.filter { $0.evaluationError != nil }.count
            store.addLog("Fetch complete: \(onCount)/\(results.count) on, \(errCount) errors")
        }

        func evaluateNext(index: Int) {
            guard index < features.count else {
                finishBatch()
                return
            }
            let featureInfo = features[index]
            Flag.isFeatureEnabled(featureInfo.key, evaluationContext: evaluationContext) { enabled in
                DispatchQueue.main.async {
                    results.append(
                        FeatureState(
                            key: featureInfo.key,
                            enabled: enabled,
                            info: featureInfo,
                            evaluationError: nil
                        )
                    )
                    store.addLog("\(featureInfo.key) -> \(enabled ? "ON" : "OFF")")
                    evaluateNext(index: index + 1)
                }
            } errorCallback: { error in
                DispatchQueue.main.async {
                    let message = "fetch_error(\(error))"
                    store.addLog("Error: \(featureInfo.key) — \(message)")
                    results.append(
                        FeatureState(
                            key: featureInfo.key,
                            enabled: false,
                            info: featureInfo,
                            evaluationError: message
                        )
                    )
                    evaluateNext(index: index + 1)
                }
            }
        }

        evaluateNext(index: 0)
    }
}

private struct FeatureStateRow: View {
    let state: FeatureState

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.info.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DemoTheme.bodyText)
                Text(state.key)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                if let error = state.evaluationError {
                    Text("Error: \(error)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.90, green: 0.32, blue: 0.0))
                }
            }
            Spacer()
            StatusChip(state: state)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct StatusChip: View {
    let state: FeatureState

    var body: some View {
        let (label, color): (String, Color) = {
            if state.evaluationError != nil { return ("ERR", DemoTheme.errorOrange) }
            return state.enabled ? ("ON", DemoTheme.onGreen) : ("OFF", DemoTheme.offGrey)
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

/// ECID / identities card with tap-to-copy, mirroring the Luma reference app.
private struct IdentitiesCard: View {
    let ecid: String
    let onRefresh: () -> Void

    var body: some View {
        DemoCard {
            HStack {
                Text("Identities")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(DemoTheme.accent)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }
            IdentityValueRow(label: "ECID", value: ecid)
                .padding(.top, 8)
        }
    }
}

private struct IdentityValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                Text(value.isEmpty ? "Not available" : value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(DemoTheme.bodyText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            if !value.isEmpty {
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(DemoTheme.accent)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Optional custom-identity injection into the evaluation context.
private struct CustomIdentityCard: View {
    @ObservedObject var store: FlagsDemoStore

    var body: some View {
        DemoCard {
            Toggle(isOn: $store.useCustomIdentity) {
                Text("Custom Identity")
                    .font(.system(size: 16, weight: .bold))
            }

            Text("When on, adds namespace + id to the evaluation context.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .padding(.top, 2)

            if store.useCustomIdentity {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Namespace")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 84, alignment: .leading)
                        TextField("ECID", text: $store.identityNamespace)
                            .font(.system(size: 13))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disableAutocorrection(true)
                    }
                    HStack(spacing: 8) {
                        Text("Identifier")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 84, alignment: .leading)
                        TextField("identity value", text: $store.identityId)
                            .font(.system(size: 13))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

/// App lifecycle FG/BG toggle to exercise polling / cache-refresh behavior.
private struct LifecycleCard: View {
    @ObservedObject var store: FlagsDemoStore

    var body: some View {
        DemoCard {
            Text("App Lifecycle")
                .font(.system(size: 16, weight: .bold))
            Text("Drives MobileCore.lifecycleStart / lifecyclePause.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .padding(.top, 2)
            Picker("", selection: Binding(
                get: { store.appState },
                set: { store.setAppState($0) }
            )) {
                Text("Foreground").tag(AppLifecycleState.foreground)
                Text("Background").tag(AppLifecycleState.background)
            }
            .pickerStyle(.segmented)
            .padding(.top, 8)
        }
    }
}

/// Runtime SDK config override (dev/testing only).
private struct ConfigOverrideCard: View {
    @ObservedObject var store: FlagsDemoStore

    var body: some View {
        DemoCard {
            Text("Config Override")
                .font(.system(size: 16, weight: .bold))
            Text("Runtime only — production apps use the Data Collection mobile property. Leave blank to skip a field.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .padding(.top, 2)

            VStack(spacing: 8) {
                configField("Client ID", text: $store.clientId)
                configField("Sandbox", text: $store.sandbox)
                configField("IMS Org", text: $store.imsOrg)
                configField("Edge Domain", text: $store.edgeDomain)
            }
            .padding(.top, 8)

            Button {
                store.applyConfigOverride()
            } label: {
                HStack {
                    Spacer()
                    Text("Apply Config")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                }
                .frame(height: 44)
            }
            .buttonStyle(DemoPrimaryButtonStyle())
            .padding(.top, 8)
        }
    }

    private func configField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 96, alignment: .leading)
            TextField(label, text: text)
                .font(.system(size: 13))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
        }
    }
}

/// On-screen, timestamped activity log with a clear action.
private struct ActivityLogCard: View {
    @ObservedObject var store: FlagsDemoStore

    var body: some View {
        DemoCard {
            HStack {
                Text("Activity Log")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Clear") { store.clearLogs() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DemoTheme.red)
                    .buttonStyle(.plain)
            }

            if store.logs.isEmpty {
                Text("No activity yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.logs) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.timestamp)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                            Text(line.message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DemoTheme.bodyText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

private struct DemoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}

private struct DemoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(DemoTheme.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .cornerRadius(12)
    }
}

/// Exercises ``Flag/getFeature(featureKey:evaluationContext:completion:)`` for a single feature key.
struct GetFeatureScreen: View {
    @EnvironmentObject private var store: FlagsDemoStore
    @State private var fetchCount = 0
    @State private var fetchLabel = ""
    @State private var isLoading = false
    @State private var featureKey = FlagDemoFetchConfig.defaultFeatureKey
    @State private var contextEntries = FlagDemoFetchConfig.defaultContextEntries
    @State private var resultText: String?
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                statusCard
                featureKeyCard
                evaluationContextCard
                interpretingCard
                getFeatureButton
                if let errorText {
                    resultCard(title: "Error", body: errorText, isError: true)
                } else if let resultText {
                    resultCard(title: "JSON Response", body: resultText, isError: false)
                }
                Spacer(minLength: 24)
            }
            .padding(16)
        }
        .background(DemoTheme.background.ignoresSafeArea())
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Get Feature")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(DemoTheme.accent)
            Text(fetchLabel.isEmpty ? "Flag.getFeature API" : "Flag.getFeature API  |  \(fetchLabel)")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
    }

    private var statusCard: some View {
        DemoCard {
            HStack(spacing: 8) {
                Circle()
                    .fill(DemoTheme.onGreen)
                    .frame(width: 10, height: 10)
                Text("Flags: ready")
                    .font(.system(size: 14, weight: .medium))
            }
        }
    }

    private var featureKeyCard: some View {
        DemoCard {
            Text("Feature Key")
                .font(.system(size: 16, weight: .bold))

            TextField("feature key", text: $featureKey)
                .font(.system(size: 13))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
                .padding(.top, 8)

            Menu {
                ForEach(FlagDemoFetchConfig.provisionFeatureKeys, id: \.self) { key in
                    Button(key) {
                        featureKey = key
                    }
                }
            } label: {
                Text("Choose provisioned key")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DemoTheme.accent)
            }
            .padding(.top, 8)
        }
    }

    private var evaluationContextCard: some View {
        DemoCard {
            HStack {
                Text("Evaluation Context")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    contextEntries.append(ContextEntry(key: "", value: ""))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(DemoTheme.accent)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("ECID")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 72, alignment: .leading)
                    Text(store.ecid.isEmpty ? "—" : store.ecid)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.vertical, 4)

                ForEach($contextEntries) { $entry in
                    HStack(spacing: 8) {
                        TextField("key", text: $entry.key)
                            .font(.system(size: 13))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                        TextField("value", text: $entry.value)
                            .font(.system(size: 13))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                        Button {
                            contextEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DemoTheme.red)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var interpretingCard: some View {
        DemoCard {
            Text("Interpreting getFeature results")
                .font(.system(size: 16, weight: .bold))
            Text(
                "Returns JSON for the FeatureEvaluationResult when a match exists, or null when no match is found."
            )
            .font(.system(size: 13))
            .foregroundColor(DemoTheme.bodyText)
            .padding(.top, 8)
            Text(
                "Orange Error card = SDK callback failed (network, IMS, or server error). Check console logs."
            )
            .font(.system(size: 13))
            .foregroundColor(DemoTheme.bodyText)
            .padding(.top, 8)
        }
    }

    private var getFeatureButton: some View {
        Button {
            evaluateFeature()
        } label: {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Get Feature")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
            }
            .frame(height: 50)
        }
        .buttonStyle(DemoPrimaryButtonStyle())
        .disabled(isLoading || featureKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func resultCard(title: String, body: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isError {
                    Circle()
                        .fill(DemoTheme.errorOrange)
                        .frame(width: 10, height: 10)
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            DemoCard {
                Text(body)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isError ? Color(red: 0.90, green: 0.32, blue: 0.0) : DemoTheme.bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func evaluateFeature() {
        let trimmedKey = featureKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        isLoading = true
        resultText = nil
        errorText = nil
        store.addLog("Calling getFeature('\(trimmedKey)')")

        let evaluationContext = store.buildEvaluationContext(from: contextEntries)

        Flag.getFeature(trimmedKey, evaluationContext: evaluationContext) { result in
            DispatchQueue.main.async {
                fetchCount += 1
                fetchLabel = "Fetch #\(fetchCount)"
                isLoading = false

                if let result {
                    resultText = result.demoJSONString()
                    store.addLog("getFeature('\(trimmedKey)') -> id=\(result.id)")
                } else {
                    resultText = "null"
                    store.addLog("getFeature('\(trimmedKey)') -> null")
                }
            }
        } errorCallback: { error in
            DispatchQueue.main.async {
                fetchCount += 1
                fetchLabel = "Fetch #\(fetchCount)"
                isLoading = false
                let message = "getFeature_error(\(error))"
                errorText = message
                store.addLog("getFeature('\(trimmedKey)') FAILED: \(message)")
            }
        }
    }

}

/// Serializes ``FeatureEvaluationResult`` to JSON using the same keys as the extension response payload.
private extension FeatureEvaluationResult {
    func demoJSONString() -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: demoJSONObject(),
            options: [.prettyPrinted, .sortedKeys]
        ),
        let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    func demoJSONObject() -> [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "key": key
        ]
        if let featureGroupKey {
            object["featureGroupKey"] = featureGroupKey
        }
        if let meta {
            object["meta"] = meta
        }
        if let analyticsParam {
            var analytics: [String: Any] = [
                "featureGroupId": analyticsParam.featureGroupId,
                "featureId": analyticsParam.featureId
            ]
            if let variantId = analyticsParam.variantId {
                analytics["variantId"] = DemoJSONValue.coerce(variantId)
            }
            object["analyticsParam"] = analytics
        }
        return object
    }
}

private enum DemoJSONValue {
    /// Preserves numeric-looking strings as JSON numbers when possible (matches SDK wire format).
    static func coerce(_ value: String) -> Any {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intValue = Int(trimmed) {
            return intValue
        }
        return value
    }
}
