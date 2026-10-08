import Foundation

enum PrivilegeError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Administrator access was cancelled."
        case .failed(let message):
            return message
        }
    }
}

/// Runs the tiny set of root commands VibeMode needs.
///
/// Order:
/// 1. `sudo -n` — works after the optional sudoers rule is installed (no prompt).
/// 2. `osascript … with administrator privileges` — standard macOS password dialog.
///
/// A signed SMAppService LaunchDaemon would be nicer long-term (one approval in
/// System Settings, then XPC). It is not used here because an app Lars builds
/// himself in Xcode is typically ad-hoc signed; `SMAppService.daemon` then fails
/// to register. A tightly scoped sudoers rule is the workable equivalent for a
/// personal machine.
enum Privilege {
    static let sudoersPath = "/etc/sudoers.d/vibemode"
    static let safetynetPlistPath = "/Library/LaunchDaemons/dk.lars.vibemode.safetynet.plist"
    static let safetynetLabel = "dk.lars.vibemode.safetynet"

    /// Toggle only `SleepDisabled`. Idle sleep is handled with a user-level
    /// IOPM assertion so we do not rewrite the rest of Energy Saver.
    static func setSleepDisabled(_ disabled: Bool) throws {
        let value = disabled ? "1" : "0"
        let pmset = ["/usr/bin/pmset", "-a", "disablesleep", value]

        if runSudoNonInteractive(pmset) {
            return
        }

        var script = "/usr/bin/pmset -a disablesleep \(value)\n"
        script += Self.ensureSafetynetShell
        try runAdministrator(script)
    }

    /// One-time install: passwordless `pmset -a disablesleep 0|1` for admin users,
    /// plus a boot LaunchDaemon that always turns SleepDisabled back off so a
    /// crash + reboot cannot leave the Mac permanently unable to sleep.
    static func installPasswordlessHelper() throws {
        try runAdministrator(installHelperShell)
    }

    static func removePasswordlessHelper() throws {
        try runAdministrator(removeHelperShell)
    }

    static func sudoersPresent() -> Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    static func safetynetPresent() -> Bool {
        FileManager.default.fileExists(atPath: safetynetPlistPath)
    }

    /// Best-effort restore from a crash path. Must not display UI.
    static func emergencyDisableSleepFlagIfPossible() {
        _ = runSudoNonInteractive(["/usr/bin/pmset", "-a", "disablesleep", "0"])
    }

    // MARK: - Execution

    private static func runSudoNonInteractive(_ args: [String]) -> Bool {
        let result = ProcessRunner.run("/usr/bin/sudo", ["-n"] + args)
        return result.exitCode == 0
    }

    static func runAdministrator(_ bashScript: String) throws {
        let b64 = Data(bashScript.utf8).base64EncodedString()
        let apple = "do shell script \"echo \(b64) | /usr/bin/base64 -D | /bin/bash\" with administrator privileges"
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", apple], timeout: 180)
        if result.exitCode == 0 { return }

        let combined = (result.stderr + "\n" + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.contains("-128") || combined.lowercased().contains("not allowed") && combined.lowercased().contains("user") {
            throw PrivilegeError.cancelled
        }
        if combined.lowercased().contains("canceled") || combined.lowercased().contains("cancelled") {
            throw PrivilegeError.cancelled
        }
        throw PrivilegeError.failed(combined.isEmpty ? "Administrator command failed." : combined)
    }

    // MARK: - Shell payloads

    /// LaunchDaemon that runs at boot and clears SleepDisabled. Harmless if the
    /// flag is already 0; essential if VibeMode died with the flag left on.
    static var ensureSafetynetShell: String {
        """
        if [ ! -f \(safetynetPlistPath) ]; then
        cat > \(safetynetPlistPath) <<'PLIST'
        \(safetynetPlist)
        PLIST
        /usr/sbin/chown root:wheel \(safetynetPlistPath)
        /bin/chmod 644 \(safetynetPlistPath)
        /bin/launchctl bootout system \(safetynetPlistPath) >/dev/null 2>&1 || true
        /bin/launchctl bootstrap system \(safetynetPlistPath) >/dev/null 2>&1 || /bin/launchctl load \(safetynetPlistPath) >/dev/null 2>&1 || true
        fi
        """
    }

    private static var installHelperShell: String {
        """
        set -e
        cat > /tmp/vibemode.sudoers <<'EOF'
        # VibeMode — passwordless toggle of the SleepDisabled flag only.
        %admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
        %admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
        EOF
        /usr/sbin/chown root:wheel /tmp/vibemode.sudoers
        /bin/chmod 440 /tmp/vibemode.sudoers
        /usr/sbin/visudo -cf /tmp/vibemode.sudoers
        /bin/mv /tmp/vibemode.sudoers \(sudoersPath)
        /usr/sbin/chown root:wheel \(sudoersPath)
        /bin/chmod 440 \(sudoersPath)

        cat > \(safetynetPlistPath) <<'PLIST'
        \(safetynetPlist)
        PLIST
        /usr/sbin/chown root:wheel \(safetynetPlistPath)
        /bin/chmod 644 \(safetynetPlistPath)
        /bin/launchctl bootout system \(safetynetPlistPath) >/dev/null 2>&1 || true
        /bin/launchctl bootstrap system \(safetynetPlistPath) >/dev/null 2>&1 || /bin/launchctl load \(safetynetPlistPath) >/dev/null 2>&1 || true
        """
    }

    private static var removeHelperShell: String {
        """
        /bin/launchctl bootout system \(safetynetPlistPath) >/dev/null 2>&1 || true
        /bin/rm -f \(safetynetPlistPath)
        /bin/rm -f \(sudoersPath)
        """
    }

    static var safetynetPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(safetynetLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/pmset</string>
                <string>-a</string>
                <string>disablesleep</string>
                <string>0</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>LaunchOnlyOnce</key>
            <true/>
        </dict>
        </plist>
        """
    }
}
