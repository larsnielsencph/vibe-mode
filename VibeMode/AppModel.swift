import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: SettingsStore {
        didSet { SettingsDisk.save(settings) }
    }
    @Published var isVibeMode = false
    @Published var isBusy = false
    @Published var statusLine = "Normal · stock macOS sleep"
    @Published var keepAliveDetail = ""
    @Published var lastError: String?
    @Published var listeners: [ListeningProcess] = []
    @Published var keptApps: [RunningAppInfo] = []
    @Published var launchAtLogin = false

    let safety = SafetyMonitor()
    private let keepAwake = KeepAwake()
    private var refreshTimer: Timer?
    private var reassertTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        settings = SettingsDisk.load()
        launchAtLogin = LoginItem.isEnabled()
        safety.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        refreshStatus()
    }

    var menuIconIsVibe: Bool { isVibeMode }

    var batteryText: String {
        if let pct = safety.batteryPercent {
            return "\(pct)%"
        }
        return "—"
    }

    var thermalText: String {
        switch safety.thermalState {
        case .nominal: return "cool"
        case .fair: return "warm"
        case .serious: return "hot"
        case .critical: return "critical heat"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Lifecycle

    func handleLaunchSafety() async {
        AppNotifications.requestPermission()
        safety.poll()

        let leftoverVibe = settings.vibeSessionDirty
        let flag = PowerSnapshot.sleepDisabledFlag()
        if leftoverVibe || (settings.lastEnabledSleepDisabled && flag == true) {
            keepAwake.emergencyExit()
            if flag == true || leftoverVibe {
                do {
                    try Privilege.setSleepDisabled(false)
                } catch {
                    Privilege.emergencyDisableSleepFlagIfPossible()
                }
            }
            settings.vibeSessionDirty = false
            settings.lastEnabledSleepDisabled = false
            isVibeMode = false
            statusLine = "Normal · restored after last session"
            AppNotifications.send(
                title: "VibeMode restored Normal",
                body: "Sleep was turned back on so a previous Vibe session cannot leave this Mac stuck awake."
            )
        }
        refreshStatus()
    }

    func emergencyRestoreToNormal() {
        keepAwake.emergencyExit()
        if isVibeMode || settings.vibeSessionDirty {
            Privilege.emergencyDisableSleepFlagIfPossible()
        }
        var next = settings
        next.vibeSessionDirty = false
        next.lastEnabledSleepDisabled = false
        settings = next
        isVibeMode = false
    }

    // MARK: - Mode switch

    func selectNormal() {
        guard !isBusy else { return }
        Task { await disableVibe(reason: "You switched back to Normal.") }
    }

    func selectVibe() {
        guard !isBusy, !isVibeMode else { return }
        Task { await enableVibe() }
    }

    func enableVibe() async {
        lastError = nil
        listeners = ListeningPorts.current()
        let toQuit = AppQuitter.appsToQuit(allowlist: settings.allowlist, listeners: listeners)

        if settings.askBeforeQuitting {
            let (proceed, dontAsk) = ConfirmQuit.run(appNames: toQuit.map(\.name))
            if dontAsk {
                settings.askBeforeQuitting = false
            }
            if !proceed {
                statusLine = "Normal · cancelled"
                return
            }
        }

        isBusy = true
        defer { isBusy = false }

        do {
            settings.vibeSessionDirty = true
            let status = try keepAwake.enterVibe(allowAdminPrompt: true)
            settings.lastEnabledSleepDisabled = status.usingAdminSleepDisabled
            isVibeMode = true
            keepAliveDetail = status.message
            _ = AppQuitter.quitGracefully(toQuit)
            beginVibeTimers()
            refreshStatus()
            if settings.warnAboutHeat {
                AppNotifications.send(
                    title: "Vibe mode is on",
                    body: "The Mac will keep running with the lid closed. A closed bag traps heat — auto-revert is set at \(settings.clampedBatteryThreshold)% battery."
                )
            }
            if !status.usingAdminSleepDisabled {
                lastError = "Closed-lid keep-awake is using the no-sudo IOKit override. Grant admin in Settings for the more reliable SleepDisabled flag (recommended in a bag / on hotspot)."
            }
        } catch {
            settings.vibeSessionDirty = false
            keepAwake.emergencyExit()
            isVibeMode = false
            lastError = error.localizedDescription
            statusLine = "Normal · could not enter Vibe"
        }
    }

    func disableVibe(reason: String) async {
        isBusy = true
        defer { isBusy = false }
        stopVibeTimers()
        keepAwake.exitVibe()
        settings.vibeSessionDirty = false
        settings.lastEnabledSleepDisabled = false
        isVibeMode = false
        keepAliveDetail = ""
        lastError = nil
        refreshStatus()
        statusLine = "Normal · stock macOS sleep"
        AppNotifications.send(title: "VibeMode is Normal", body: reason)
    }

    // MARK: - Settings actions

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            launchAtLogin = LoginItem.isEnabled()
        } catch {
            lastError = error.localizedDescription
            launchAtLogin = LoginItem.isEnabled()
        }
    }

    func installPasswordlessHelper() {
        isBusy = true
        defer { isBusy = false }
        do {
            try Privilege.installPasswordlessHelper()
            settings.sudoersInstalled = Privilege.sudoersPresent()
            keepAliveDetail = "Password-free pmset + boot safety net installed."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removePasswordlessHelper() {
        isBusy = true
        defer { isBusy = false }
        do {
            try Privilege.removePasswordlessHelper()
            settings.sudoersInstalled = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resetAllowlist() {
        settings.allowlist = AllowlistItem.factoryDefaults
    }

    func addAppToAllowlist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app that should stay open in Vibe mode."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let bid = bundle?.bundleIdentifier ?? ""
        let process = url.deletingPathExtension().lastPathComponent
        var item = AllowlistItem(name: name, bundleIDs: bid.isEmpty ? [] : [bid], processNames: [process])
        if settings.allowlist.contains(where: { $0.bundleIDs.contains(bid) && !bid.isEmpty }) {
            return
        }
        item.id = UUID()
        settings.allowlist.append(item)
    }

    func removeAllowlist(_ item: AllowlistItem) {
        settings.allowlist.removeAll { $0.id == item.id }
    }

    func refreshStatus() {
        listeners = ListeningPorts.current()
        keptApps = AppQuitter.appsKept(allowlist: settings.allowlist, listeners: listeners)
        safety.poll()
        settings.sudoersInstalled = Privilege.sudoersPresent()
        launchAtLogin = LoginItem.isEnabled()

        let kept = keptSummary()
        if isVibeMode {
            statusLine = "Battery \(batteryText) · keeping \(kept)"
        } else {
            statusLine = "Battery \(batteryText) · Normal"
        }
    }

    func keptSummary() -> String {
        var labels: [String] = keptApps.map(\.name)
        let keptPIDs = Set(keptApps.map(\.pid))
        for listener in listeners where !keptPIDs.contains(listener.pid) {
            labels.append(listener.shortLabel)
        }
        let unique = labels.reduce(into: [String]()) { acc, next in
            if !acc.contains(where: { $0.caseInsensitiveCompare(next) == .orderedSame }) {
                acc.append(next)
            }
        }
        if unique.isEmpty { return "allowlisted tools & local ports" }
        if unique.count <= 4 { return unique.joined(separator: ", ") }
        return unique.prefix(3).joined(separator: ", ") + " +\(unique.count - 3)"
    }

    // MARK: - Timers

    private func beginVibeTimers() {
        stopVibeTimers()
        safety.start(
            thresholdPercent: settings.clampedBatteryThreshold,
            onBatteryBelow: { [weak self] percent in
                Task { @MainActor in
                    await self?.disableVibe(reason: "Battery dropped to \(percent)%. Restored Normal so the Mac can sleep.")
                }
            },
            onCriticalHeat: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if self.settings.warnAboutHeat {
                        AppNotifications.send(
                            title: "VibeMode heat warning",
                            body: "macOS reports critical thermal pressure. The lid is closed and airflow is limited."
                        )
                    }
                    if self.settings.autoRevertOnCriticalHeat {
                        await self.disableVibe(reason: "Critical heat — restored Normal so the Mac can sleep.")
                    }
                }
            }
        )
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        reassertTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.keepAwake.reassert() }
        }
        if settings.warnAboutHeat, safety.thermalState == .serious || safety.thermalState == .critical {
            AppNotifications.send(
                title: "VibeMode heat warning",
                body: "This Mac is already warm. A closed lid in a bag will trap more heat."
            )
        }
    }

    private func stopVibeTimers() {
        safety.stop()
        refreshTimer?.invalidate()
        refreshTimer = nil
        reassertTimer?.invalidate()
        reassertTimer = nil
    }

}
