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
        let needles = (processNames + [name])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let candidates = [localizedName, processName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for candidate in candidates {
            for needle in needles where Self.name(candidate, matchesApp: needle) {
                return true
            }
        }
        return false
    }

    /// Exact name, or Electron helpers like "ChatGPT Helper (Renderer)".
    static func name(_ candidate: String, matchesApp needle: String) -> Bool {
        if candidate.caseInsensitiveCompare(needle) == .orderedSame { return true }
        return candidate.lowercased().hasPrefix(needle.lowercased() + " ")
    }

    func coversSameApp(as other: AllowlistItem) -> Bool {
        if name.caseInsensitiveCompare(other.name) == .orderedSame { return true }
        let mine = Set(bundleIDs.map { $0.lowercased() })
        let theirs = Set(other.bundleIDs.map { $0.lowercased() })
        return !mine.isDisjoint(with: theirs)
    }

    mutating func mergeIdentifiers(from other: AllowlistItem) {
        for bid in other.bundleIDs where !bundleIDs.contains(where: { $0.caseInsensitiveCompare(bid) == .orderedSame }) {
            bundleIDs.append(bid)
        }
        for proc in other.processNames where !processNames.contains(where: { $0.caseInsensitiveCompare(proc) == .orderedSame }) {
            processNames.append(proc)
        }
    }

    static func mergingFactoryDefaults(into existing: [AllowlistItem]) -> [AllowlistItem] {
        var result = existing
        for factory in factoryDefaults {
            if let index = result.firstIndex(where: { $0.coversSameApp(as: factory) }) {
                result[index].mergeIdentifiers(from: factory)
            } else {
                result.append(factory)
            }
        }
        return result
    }
}

extension AllowlistItem {
    /// Coding agents and chat apps stay open in Vibe. Terminals too.
    /// Dev servers are kept separately because they listen on a local TCP port.
    /// ChatGPT.app currently ships as bundle id `com.openai.codex`.
    static let factoryDefaults: [AllowlistItem] = [
        AllowlistItem(
            name: "Claude",
            bundleIDs: [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude",
                "ai.anthropic.claude",
                "com.anthropic.claude-desktop",
                "com.anthropic.claude-code-url-handler"
            ],
            processNames: ["Claude", "claude", "Claude Code URL Handler"]
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
            name: "ChatGPT",
            bundleIDs: [
                "com.openai.codex",
                "com.openai.chatgpt",
                "com.openai.chat",
                "com.openai.Codex"
            ],
            processNames: ["ChatGPT", "Codex", "codex"]
        ),
        AllowlistItem(
            name: "Grok Bot",
            bundleIDs: [
                "com.anysphere.sand",
                "com.xai.Grok",
                "com.xai.grok",
                "ai.xai.grok"
            ],
            processNames: ["Grok Bot", "GrokBot", "Grok"]
        ),
        AllowlistItem(
            name: "Gemini",
            bundleIDs: ["com.google.GeminiMacOS"],
            processNames: ["Gemini"]
        ),
        AllowlistItem(
            name: "Perplexity",
            bundleIDs: ["ai.perplexity.macv3", "ai.perplexity.Perplexity"],
            processNames: ["Perplexity"]
        ),
        AllowlistItem(
            name: "Codex Usage",
            bundleIDs: ["com.larsnielsen.CodexSessionStatus"],
            processNames: ["CodexSessionStatus", "Codex Usage"]
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
