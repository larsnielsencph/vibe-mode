import Foundation

/// Persisted preferences. Keep this a plain Codable store so a crash cannot
/// leave "mystery" power state without a matching flag we can inspect on launch.
struct SettingsStore: Codable, Equatable {
    var allowlist: [AllowlistItem]
    var batteryThresholdPercent: Int
    var askBeforeQuitting: Bool
    var warnAboutHeat: Bool
    var autoRevertOnCriticalHeat: Bool
    var sudoersInstalled: Bool
    var lastEnabledSleepDisabled: Bool

    /// True while the user last asked for Vibe. Used on launch to restore Normal
    /// if the previous session crashed before it could clean up.
    var vibeSessionDirty: Bool

    static let `default` = SettingsStore(
        allowlist: AllowlistItem.factoryDefaults,
        batteryThresholdPercent: 15,
        askBeforeQuitting: true,
        warnAboutHeat: true,
        autoRevertOnCriticalHeat: true,
        sudoersInstalled: false,
        lastEnabledSleepDisabled: false,
        vibeSessionDirty: false
    )

    var clampedBatteryThreshold: Int {
        min(90, max(5, batteryThresholdPercent))
    }
}

enum SettingsDisk {
    private static let filename = "settings.json"

    private static var fileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = root.appendingPathComponent("VibeMode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    static func load() -> SettingsStore {
        guard let data = try? Data(contentsOf: fileURL) else { return .default }
        guard var decoded = try? JSONDecoder().decode(SettingsStore.self, from: data) else {
            return .default
        }
        let merged = AllowlistItem.mergingFactoryDefaults(into: decoded.allowlist)
        if merged != decoded.allowlist {
            decoded.allowlist = merged
            save(decoded)
        }
        return decoded
    }

    static func save(_ store: SettingsStore) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
