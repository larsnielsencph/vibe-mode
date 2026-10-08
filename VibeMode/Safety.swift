import AppKit
import Combine
import Foundation
import IOKit.ps
import ServiceManagement
import UserNotifications

@MainActor
final class SafetyMonitor: ObservableObject {
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var isOnAC: Bool = false
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var lastEvent: String?

    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var onBatteryBelow: ((Int) -> Void)?
    private var onCriticalHeat: (() -> Void)?
    private var threshold: Int = 15
    private var didFireBattery = false
    private var didFireHeat = false

    func start(
        thresholdPercent: Int,
        onBatteryBelow: @escaping (Int) -> Void,
        onCriticalHeat: @escaping () -> Void
    ) {
        stop()
        threshold = thresholdPercent
        self.onBatteryBelow = onBatteryBelow
        self.onCriticalHeat = onCriticalHeat
        didFireBattery = false
        didFireHeat = false
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
        onBatteryBelow = nil
        onCriticalHeat = nil
    }

    func poll() {
        let snapshot = BatteryInfo.current()
        batteryPercent = snapshot.percent
        isOnAC = snapshot.isOnAC
        thermalState = ProcessInfo.processInfo.thermalState

        if let percent = snapshot.percent, !snapshot.isOnAC, percent <= threshold, !didFireBattery {
            didFireBattery = true
            lastEvent = "Battery \(percent)% — reverting to Normal."
            onBatteryBelow?(percent)
        }
        if thermalState == .critical, !didFireHeat {
            didFireHeat = true
            lastEvent = "Thermal pressure is critical."
            onCriticalHeat?()
        }
    }
}

struct BatteryInfo {
    var percent: Int?
    var isOnAC: Bool

    static func current() -> BatteryInfo {
        var percent: Int?
        var ac = false
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return BatteryInfo(percent: nil, isOnAC: false)
        }
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as NSArray?
        guard let list else {
            return BatteryInfo(percent: nil, isOnAC: false)
        }

        for source in list {
            let cfSource = source as AnyObject
            guard let desc = IOPSGetPowerSourceDescription(blob, cfSource)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int,
               max > 0 {
                percent = Int((Double(capacity) / Double(max) * 100).rounded())
            } else if let capacity = desc[kIOPSCurrentCapacityKey] as? Int, capacity <= 100 {
                percent = capacity
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                ac = state == kIOPSACPowerValue
            }
        }
        return BatteryInfo(percent: percent, isOnAC: ac)
    }
}

enum AppNotifications {
    static let category = "dk.lars.vibemode"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

enum LoginItem {
    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum ConfirmQuit {
    @MainActor
    static func run(appNames: [String]) -> (proceed: Bool, dontAskAgain: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Switch to Vibe mode?"
        if appNames.isEmpty {
            alert.informativeText = "No extra apps need to quit. Coding tools, terminals, and anything listening on a local port stay running."
        } else {
            let listed = appNames.prefix(18).joined(separator: "\n")
            let extra = appNames.count > 18 ? "\n…and \(appNames.count - 18) more" : ""
            alert.informativeText = "These apps will be asked to quit (normal Quit, so they can save):\n\n\(listed)\(extra)\n\nFinder, system processes, VibeMode, allowlisted apps, and anything listening on a local TCP port are left alone."
        }
        alert.addButton(withTitle: "Quit apps and start Vibe")
        alert.addButton(withTitle: "Cancel")

        let checkbox = NSButton(checkboxWithTitle: "Don’t ask again", target: nil, action: nil)
        checkbox.state = .off
        alert.accessoryView = checkbox

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return (response == .alertFirstButtonReturn, checkbox.state == .on)
    }
}
