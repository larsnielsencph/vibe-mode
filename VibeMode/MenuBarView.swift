import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text(model.statusLine)

        if model.isVibeMode && !model.keepAliveDetail.isEmpty {
            Text(model.keepAliveDetail)
        }

        Divider()

        Button {
            model.selectVibe()
        } label: {
            Text(model.isVibeMode ? "✓  Vibe mode" : "     Vibe mode")
        }
        .disabled(model.isBusy || model.isVibeMode)
        .keyboardShortcut("v")

        Button {
            model.selectNormal()
        } label: {
            Text(model.isVibeMode ? "     Normal mode" : "✓  Normal mode")
        }
        .disabled(model.isBusy || !model.isVibeMode)
        .keyboardShortcut("n")

        if model.isBusy {
            Text("Working…")
        }

        if let err = model.lastError, !err.isEmpty {
            Text(err)
        }

        if model.isVibeMode, model.settings.warnAboutHeat,
           model.safety.thermalState == .serious || model.safety.thermalState == .critical {
            Text("Heat: \(model.thermalText). Open the bag or switch to Normal.")
        }

        Divider()

        Text("Kept alive")
        ForEach(Array(model.keptApps.prefix(8))) { app in
            Text("\(app.name) · \(app.reasonKept?.menuText ?? "")")
        }
        ForEach(Array(extraListenerLabels().prefix(6)), id: \.self) { label in
            Text(label)
        }
        if model.keptApps.isEmpty && model.listeners.isEmpty {
            Text("Allowlisted apps and local TCP listeners")
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Button("Refresh status") {
            model.refreshStatus()
        }

        Divider()

        Button("Quit VibeMode") {
            model.emergencyRestoreToNormal()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func extraListenerLabels() -> [String] {
        let kept = Set(model.keptApps.map(\.pid))
        return model.listeners
            .filter { !kept.contains($0.pid) }
            .map(\.shortLabel)
    }
}
