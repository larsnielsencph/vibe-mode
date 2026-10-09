import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftThreshold: Double = 15

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            allowlistTab
                .tabItem { Label("Allowlist", systemImage: "checkmark.shield") }
            powerTab
                .tabItem { Label("Power", systemImage: "bolt.horizontal") }
        }
        .frame(width: 560, height: 520)
        .onAppear {
            draftThreshold = Double(model.settings.clampedBatteryThreshold)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch VibeMode at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.toggleLaunchAtLogin($0) }
                ))
                Text("Recommended. After a reboot the app restores Normal so SleepDisabled cannot stick.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                HStack {
                    Text("Revert to Normal below")
                    Spacer()
                    Text("\(Int(draftThreshold))%")
                        .monospacedDigit()
                }
                Slider(value: $draftThreshold, in: 5...40, step: 1) { editing in
                    if !editing {
                        model.settings.batteryThresholdPercent = Int(draftThreshold)
                    }
                }
                Toggle("Warn about heat when entering Vibe", isOn: boolBinding(\.warnAboutHeat))
                Toggle("Auto-revert on critical thermal pressure", isOn: boolBinding(\.autoRevertOnCriticalHeat))
                Toggle("Ask before quitting apps", isOn: boolBinding(\.askBeforeQuitting))
            }

            Section("Now") {
                LabeledContent("Battery", value: model.batteryText)
                LabeledContent("Power", value: model.safety.isOnAC ? "Power adapter" : "Battery")
                LabeledContent("Heat", value: model.thermalText)
                LabeledContent("Mode", value: model.isVibeMode ? "Vibe" : "Normal")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var allowlistTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps on this list stay open in Vibe mode, together with anything already listening on a local TCP port (dev servers). ChatGPT, Codex, Claude, Cursor, Grok Bot and their helpers are included by default. Safari, Slack, Mail and similar stay off the list and are asked to Quit.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(model.settings.allowlist) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline)
                            if !item.bundleIDs.isEmpty {
                                Text(item.bundleIDs.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            if !item.processNames.isEmpty {
                                Text("Process: \(item.processNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.removeAllowlist(item)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Button("Add app…") { model.addAppToAllowlist() }
                Button("Restore defaults") { model.resetAllowlist() }
                Spacer()
            }
        }
        .padding(20)
    }

    private var powerTab: some View {
        Form {
            Section("Closed-lid keep-awake") {
                Text("Vibe mode uses `pmset -a disablesleep 1` (needs admin) plus an unprivileged IOKit lid override and an idle-sleep assertion. Switching to Normal restores the original SleepDisabled value and releases those holds.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("SleepDisabled now", value: flagText)
                LabeledContent("Password-free sudoers", value: model.settings.sudoersInstalled ? "Installed" : "Not installed")
                LabeledContent("Boot safety net", value: Privilege.safetynetPresent() ? "Installed" : "Not installed")

                Button("Install password-free toggle + boot safety net…") {
                    model.installPasswordlessHelper()
                }
                Text("Writes a visudo-checked rule that only allows `pmset -a disablesleep 0` and `… 1`, and a LaunchDaemon that clears the flag at boot. One admin password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Remove helper", role: .destructive) {
                    model.removePasswordlessHelper()
                }
                .disabled(!model.settings.sudoersInstalled && !Privilege.safetynetPresent())
            }

            Section("If something goes wrong") {
                Text("In Terminal, this always restores stock lid sleep:")
                    .font(.callout)
                Text("sudo pmset -a disablesleep 0")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var flagText: String {
        switch PowerSnapshot.sleepDisabledFlag() {
        case true: return "1 (sleep disabled)"
        case false: return "0 (sleep allowed)"
        case nil: return "not set (stock)"
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SettingsStore, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0 }
        )
    }
}
