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
        if let bundleID, Self.bundleID(bundleID, matchesAnyOf: bundleIDs) {
            return true
        }
        let candidates = [localizedName, processName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in candidates where !candidate.isEmpty {
            if processNames.contains(where: { Self.displayName(candidate, matchesStem: $0) }) {
                return true
            }
            if Self.displayName(candidate, matchesStem: name) {
                return true
            }
        }
        return false
    }

    /// Exact bundle ID, plus Electron/XPC helpers (`com.openai.codex.helper`).
    static func bundleID(_ bundleID: String, matchesAnyOf allowed: [String]) -> Bool {
        let needle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        for allowedID in allowed where !allowedID.isEmpty {
            if needle.caseInsensitiveCompare(allowedID) == .orderedSame {
                return true
            }
            if needle.lowercased().hasPrefix(allowedID.lowercased() + ".") {
                return true
            }
        }
        return false
    }

    /// "ChatGPT" also keeps "ChatGPT Helper (Renderer)" and "ChatGPT Classic".
    static func displayName(_ candidate: String, matchesStem stem: String) -> Bool {
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !stem.isEmpty else { return false }
        if value.caseInsensitiveCompare(stem) == .orderedSame {
            return true
        }
        let lower = value.lowercased()
        let stemLower = stem.lowercased()
        if lower.hasPrefix(stemLower + " ") || lower.hasPrefix(stemLower + "-") {
            return true
        }
        return false
    }
}

extension AllowlistItem {
    /// Coding agents and terminals stay open in Vibe mode. Dev servers are kept
    /// separately because they listen on a local TCP port.
    static let factoryDefaults: [AllowlistItem] = [
        AllowlistItem(
            name: "ChatGPT",
            bundleIDs: [
                "com.openai.chat",
                "com.openai.chatgpt",
                "com.openai.codex"
            ],
            processNames: ["ChatGPT", "ChatGPT Classic"]
        ),
        AllowlistItem(
            name: "Codex",
            bundleIDs: [
                "com.openai.codex",
                "com.openai.chat"
            ],
            processNames: ["Codex", "codex"]
        ),
        AllowlistItem(
            name: "Claude",
            bundleIDs: [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude",
                "ai.anthropic.claude",
                "com.anthropic.claude-desktop",
                "com.anthropic.claude-code"
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
            name: "Grok Bot",
            bundleIDs: [
                "com.anysphere.sand",
                "co.anysphere.grok-bot-computer-use",
                "com.xai.grok",
                "ai.xai.grok"
            ],
            processNames: ["Grok Bot", "Grokbot", "Grok"]
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

    /// Coding agents that must stay open even if an older `settings.json` omitted them.
    /// Terminals are left as the user last saved them.
    static let requiredAgentNames: [String] = [
        "ChatGPT", "Codex", "Claude", "Cursor", "Grok Bot"
    ]

    /// Fold required coding-agent apps (and extra bundle IDs) into a previously saved list.
    static func mergingFactoryDefaults(into existing: [AllowlistItem]) -> [AllowlistItem] {
        var result = existing
        for factory in factoryDefaults where requiredAgentNames.contains(where: {
            $0.caseInsensitiveCompare(factory.name) == .orderedSame
        }) {
            if let index = result.firstIndex(where: {
                $0.name.caseInsensitiveCompare(factory.name) == .orderedSame
            }) {
                var item = result[index]
                item.bundleIDs = unioning(item.bundleIDs, factory.bundleIDs)
                item.processNames = unioning(item.processNames, factory.processNames)
                result[index] = item
            } else {
                result.append(factory)
            }
        }
        return result
    }

    private static func unioning(_ existing: [String], _ incoming: [String]) -> [String] {
        var result = existing
        for value in incoming where !value.isEmpty {
            if !result.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                result.append(value)
            }
        }
        return result
    }
}
