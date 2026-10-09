import AppKit
import CoreWLAN
import Foundation
import SystemConfiguration

/// Live Wi-Fi / routing facts used before entering Vibe.
struct NetworkSnapshot: Equatable {
    var wifiHardwareOn: Bool
    var wifiAssociated: Bool
    var ssid: String?
    var hasDefaultRoute: Bool
}

/// Whether this Mac already has a network agents can use with the lid closed.
enum NetworkReadiness: Equatable {
    case ready(networkName: String?)
    case wifiOff
    case notJoined

    var shouldWarnBeforeVibe: Bool {
        switch self {
        case .ready: return false
        case .wifiOff, .notJoined: return true
        }
    }

    var menuLabel: String {
        switch self {
        case .ready(let name):
            if let name, !name.isEmpty { return name }
            return "Wi-Fi"
        case .wifiOff:
            return "Wi-Fi off"
        case .notJoined:
            return "no hotspot"
        }
    }

    var alertTitle: String {
        "No Wi-Fi or hotspot"
    }

    var alertBody: String {
        switch self {
        case .ready:
            return ""
        case .wifiOff:
            return "Wi-Fi is off. Join your iPhone hotspot (or any Wi-Fi) before closing the lid, or coding agents will have no network."
        case .notJoined:
            return "This Mac is not on a Wi-Fi network. Join your iPhone hotspot first, then try Vibe again — a closed lid cannot join a network by itself."
        }
    }

    static func from(_ snap: NetworkSnapshot) -> NetworkReadiness {
        let trimmed = snap.ssid?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed?.isEmpty == false) ? trimmed : nil
        if snap.hasDefaultRoute || snap.wifiAssociated {
            return .ready(networkName: name)
        }
        if !snap.wifiHardwareOn {
            return .wifiOff
        }
        return .notJoined
    }

    static func current() -> NetworkReadiness {
        from(capture())
    }

    static func capture() -> NetworkSnapshot {
        let iface = CWWiFiClient.shared().interface()
        return NetworkSnapshot(
            wifiHardwareOn: iface?.powerOn() ?? false,
            wifiAssociated: iface?.serviceActive() ?? false,
            ssid: iface?.ssid(),
            hasDefaultRoute: hasDefaultRoute()
        )
    }
}

enum ConfirmNetwork {
    @MainActor
    static func run(_ readiness: NetworkReadiness) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = readiness.alertTitle
        alert.informativeText = readiness.alertBody
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Continue anyway")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}

private func hasDefaultRoute() -> Bool {
    if let store = SCDynamicStoreCreate(nil, "dk.lars.vibemode" as CFString, nil, nil) {
        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6"
        ]
        for key in keys {
            if let info = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
               let iface = info["PrimaryInterface"] as? String,
               !iface.isEmpty {
                return true
            }
        }
    }
    return false
}
