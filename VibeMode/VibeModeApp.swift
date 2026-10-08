import AppKit
import SwiftUI

@main
struct VibeModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(isVibe: model.isVibeMode, isBusy: model.isBusy)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// Menu bar glyph: moon when stock sleep is on, bolt when Vibe is holding the machine awake.
struct MenuBarLabel: View {
    let isVibe: Bool
    let isBusy: Bool

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(isVibe ? "VibeMode: Vibe" : "VibeMode: Normal")
    }

    private var iconName: String {
        if isBusy { return "ellipsis.circle" }
        return isVibe ? "bolt.horizontal.fill" : "moon.zzz"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            await AppModel.shared.handleLaunchSafety()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.emergencyRestoreToNormal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
