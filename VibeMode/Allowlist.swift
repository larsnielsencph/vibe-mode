import Foundation

/// One keep-alive rule. Matches a running app by bundle identifier and/or process name.
struct AllowlistItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var bundleIDs: [String]
    var processNames: [String]

    init(
        id: UUID = UUID(),
        name: String,
        bundleIDs: [String] = [],
        processNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.processNames = processNames
    }

    var summary: String {
        let ids = bundleIDs.filter { !$0.isEmpty }
        let procs = processNames.filter { !$0.isEmpty }
        if ids.isEmpty && procs.isEmpty { return name }
        return ([name] + ids + procs).joined(separator: " · ")
    }

    func matches(bundleID: String?, localizedName: String?, processName: String?) -> Bool {
        if let bundleID, bundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            return true
        }
        let candidates = [localizedName, processName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in candidates where !candidate.isEmpty {
            if processNames.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return true
            }
            if name.caseInsensitiveCompare(candidate) == .orderedSame {
                return true
            }
        }
        return false
    }
}

extension AllowlistItem {
    /// Spoken intent: Claude (app + CLI), Cursor, terminals. Dev servers are
    /// kept separately because they listen on a local TCP port.
    static let factoryDefaults: [AllowlistItem] = [
        AllowlistItem(
            name: "Claude",
            bundleIDs: [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude",
                "ai.anthropic.claude",
                "com.anthropic.claude-desktop"
            ],
            processNames: ["Claude", "claude"]
        ),
        AllowlistItem(
            name: "Cursor",
            bundleIDs: [
                "com.todesktop.230313mzl4w4u92",
                "com.cursor.Cursor",
                "com.cursor.cursor"
            ],
            processNames: ["Cursor", "cursor"]
        ),
        AllowlistItem(
            name: "Terminal",
            bundleIDs: ["com.apple.Terminal"],
            processNames: ["Terminal"]
        ),
        AllowlistItem(
            name: "iTerm2",
            bundleIDs: ["com.googlecode.iterm2"],
            processNames: ["iTerm2", "iTerm"]
        ),
        AllowlistItem(
            name: "Warp",
            bundleIDs: [
                "dev.warp.Warp-Stable",
                "dev.warp.Warp",
                "dev.warp.Warp-Preview"
            ],
            processNames: ["Warp"]
        ),
        AllowlistItem(
            name: "Ghostty",
            bundleIDs: [
                "com.mitchellh.ghostty",
                "com.ghostty.Ghostty"
            ],
            processNames: ["Ghostty"]
        )
    ]
}
