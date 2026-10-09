import AppKit
import Foundation

struct RunningAppInfo: Identifiable, Equatable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    let bundleID: String?
    let bundleURL: URL?
    let reasonKept: KeepReason?
}

enum KeepReason: Equatable {
    case thisApp
    case system
    case allowlist(String)
    case listeningPort(String)

    var menuText: String {
        switch self {
        case .thisApp: return "VibeMode"
        case .system: return "system"
        case .allowlist(let name): return name
        case .listeningPort(let label): return "port \(label)"
        }
    }
}

enum AppQuitter {
    private static let ourBundleID = "dk.lars.vibemode"

    /// User-facing apps that Vibe would quit (not allowlisted, not listening, not system).
    static func appsToQuit(allowlist: [AllowlistItem], listeners: [ListeningProcess]) -> [RunningAppInfo] {
        classified(allowlist: allowlist, listeners: listeners)
            .filter { $0.reasonKept == nil }
    }

    /// User-facing apps that will stay running, plus why.
    static func appsKept(allowlist: [AllowlistItem], listeners: [ListeningProcess]) -> [RunningAppInfo] {
        classified(allowlist: allowlist, listeners: listeners)
            .filter { $0.reasonKept != nil && $0.reasonKept != .system && $0.reasonKept != .thisApp }
    }

    static func classified(allowlist: [AllowlistItem], listeners: [ListeningProcess]) -> [RunningAppInfo] {
        let listenerPIDs = Set(listeners.map(\.pid))
        let listenerByPID = Dictionary(uniqueKeysWithValues: listeners.map { ($0.pid, $0) })

        return NSWorkspace.shared.runningApplications.compactMap { app -> RunningAppInfo? in
            guard isUserFacing(app) else { return nil }
            let info = RunningAppInfo(
                pid: app.processIdentifier,
                name: displayName(for: app),
                bundleID: app.bundleIdentifier,
                bundleURL: app.bundleURL,
                reasonKept: keepReason(
                    for: app,
                    allowlist: allowlist,
                    listenerPIDs: listenerPIDs,
                    listenerByPID: listenerByPID
                )
            )
            return info
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Graceful quit only (`terminate()` sends the same Apple Event as Cmd-Q).
    /// Never `forceTerminate()`, never `kill`, never touch prohibited/system processes.
    @discardableResult
    static func quitGracefully(_ targets: [RunningAppInfo]) -> [String] {
        let us = ProcessInfo.processInfo.processIdentifier
        var sent: [String] = []
        for target in targets {
            if target.pid == us { continue }
            if target.reasonKept != nil { continue }
            guard let app = NSRunningApplication(processIdentifier: target.pid) else { continue }
            if !isUserFacing(app) { continue }
            if app.terminate() {
                sent.append(target.name)
            }
        }
        return sent
    }

    static func isUserFacing(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        if app.activationPolicy == .prohibited { return false }
        guard let path = app.bundleURL?.resolvingSymlinksInPath().path else { return false }
        if path.hasPrefix("/System/Library") { return false }
        if path.hasPrefix("/Library/Apple") { return false }
        if path.hasPrefix("/usr/") { return false }
        if path.contains(".appex/") || path.hasSuffix(".appex") { return false }
        if app.bundleIdentifier == "com.apple.loginwindow" { return false }
        return true
    }

    private static func keepReason(
        for app: NSRunningApplication,
        allowlist: [AllowlistItem],
        listenerPIDs: Set<Int32>,
        listenerByPID: [Int32: ListeningProcess]
    ) -> KeepReason? {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return .thisApp
        }
        if app.bundleIdentifier == ourBundleID {
            return .thisApp
        }
        if isProtectedSystem(app) {
            return .system
        }

        let processName = app.executableURL?.deletingPathExtension().lastPathComponent
        if let item = allowlist.first(where: {
            $0.matches(
                bundleID: app.bundleIdentifier,
                localizedName: app.localizedName,
                processName: processName
            )
        }) {
            return .allowlist(item.name)
        }
        if let item = AllowlistItem.factoryDefaults.first(where: { factory in
            AllowlistItem.requiredAgentNames.contains(where: {
                $0.caseInsensitiveCompare(factory.name) == .orderedSame
            }) && factory.matches(
                bundleID: app.bundleIdentifier,
                localizedName: app.localizedName,
                processName: processName
            )
        }) {
            return .allowlist(item.name)
        }

        if listenerPIDs.contains(app.processIdentifier), let listener = listenerByPID[app.processIdentifier] {
            return .listeningPort(listener.shortLabel)
        }

        return nil
    }

    /// Finder and the Dock are user-visible but quitting them is hostile and
    /// pointless for battery/RAM. Never quit them.
    private static func isProtectedSystem(_ app: NSRunningApplication) -> Bool {
        let protected: Set<String> = [
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.systemuiserver",
            "com.apple.notificationcenterui",
            "com.apple.controlcenter",
            "com.apple.Spotlight",
            "com.apple.WindowManager",
            "com.apple.wallpaper",
            "com.apple.dock.extra",
            "com.apple.UserNotificationCenter"
        ]
        if let bid = app.bundleIdentifier, protected.contains(bid) {
            return true
        }
        if let path = app.bundleURL?.path, path.hasPrefix("/System/Library/CoreServices") {
            return true
        }
        return false
    }

    private static func displayName(for app: NSRunningApplication) -> String {
        if let name = app.localizedName, !name.isEmpty { return name }
        if let bid = app.bundleIdentifier { return bid }
        return "pid \(app.processIdentifier)"
    }
}
