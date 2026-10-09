import CoreWLAN
import Darwin
import Darwin.Mach
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// How VibeMode holds the machine awake.
///
/// Lid-close sleep is a separate trigger from idle sleep. `caffeinate` and
/// Amphetamine-style IOPM assertions stop idle sleep; they do **not** stop a
/// MacBook from sleeping when the lid closes.
///
/// Two lid-close overrides exist on current macOS:
///
/// 1. `pmset -a disablesleep 1` (`SleepDisabled`). This is the documented
///    reliable switch. It needs root, is system-wide, and **persists across
///    reboot** until set back to 0. That persistence is why we snapshot the
///    original value, restore it on Normal / quit / launch, and install a boot
///    LaunchDaemon that clears the flag.
/// 2. IOKit `kPMSetClamshellSleepState` (selector 12 on `IOPMrootDomain`).
///    Unprivileged, does not persist across reboot, and can be cleared by macOS
///    on power-source changes (charger / hotspot). Treated as a supplement and
///    as a fallback if the user declines the admin prompt.
///
/// Vibe applies both, plus an idle-sleep assertion, then periodically re-applies
/// the IOKit flag and Wi-Fi power so a Personal Hotspot flap does not drop us.
struct KeepAwakeStatus: Equatable {
    var sleepDisabled: Bool
    var clamshellOverride: Bool
    var assertionHeld: Bool
    var usingAdminSleepDisabled: Bool
    var message: String

    var lidClosedLikelyWorks: Bool {
        sleepDisabled || clamshellOverride
    }
}

enum KeepAwakeError: LocalizedError {
    case couldNotStayAwake(String)

    var errorDescription: String? {
        switch self {
        case .couldNotStayAwake(let message):
            return message
        }
    }
}

final class KeepAwake {
    private var assertionID: IOPMAssertionID = 0
    private var assertionHeld = false
    private var snapshot: PowerSnapshot?
    private var ioConnect: io_connect_t = 0
    private var ioService: io_object_t = 0
    /// True only when this session successfully turned SleepDisabled on.
    private var didEnableSleepDisabled = false

    deinit {
        emergencyExit()
    }

    func enterVibe(allowAdminPrompt: Bool) throws -> KeepAwakeStatus {
        let snap = PowerSnapshot.capture()
        snapshot = snap

        takeIdleAssertion()
        let clamshell = applyClamshellOverride(disableLidSleep: true)
        tryKeepWiFiPowered()

        var usedAdmin = false
        var adminError: String?
        if snap.sleepDisabled != true {
            do {
                if allowAdminPrompt {
                    try Privilege.setSleepDisabled(true)
                    usedAdmin = true
                } else if runSilentSleepDisabled(true) {
                    usedAdmin = true
                }
            } catch PrivilegeError.cancelled {
                adminError = "Admin prompt cancelled — using the no-sudo lid override only."
            } catch {
                adminError = error.localizedDescription
            }
        } else {
            usedAdmin = true
        }

        let verified = PowerSnapshot.sleepDisabledFlag()
        let status = KeepAwakeStatus(
            sleepDisabled: verified == true,
            clamshellOverride: clamshell,
            assertionHeld: assertionHeld,
            usingAdminSleepDisabled: usedAdmin && verified == true,
            message: Self.describe(
                sleepDisabled: verified == true,
                clamshell: clamshell,
                assertion: assertionHeld,
                adminError: adminError
            )
        )

        if verified == true, snap.sleepDisabled != true {
            didEnableSleepDisabled = true
        }

        if !status.lidClosedLikelyWorks {
            releaseEverything(restoreSleepDisabled: true)
            throw KeepAwakeError.couldNotStayAwake(
                "Could not override lid-close sleep. \(status.message) Grant the admin prompt so VibeMode can set SleepDisabled."
            )
        }
        return status
    }

    func exitVibe() {
        releaseEverything(restoreSleepDisabled: true)
    }

    /// Called from terminate / crash-adjacent paths. Never prompts.
    func emergencyExit() {
        applyClamshellOverride(disableLidSleep: false)
        releaseIdleAssertion()
        closeIOKit()
        Privilege.emergencyDisableSleepFlagIfPossible()
        if didEnableSleepDisabled, snapshot?.sleepDisabled != true {
            _ = runSilentSleepDisabled(false)
        }
        didEnableSleepDisabled = false
        snapshot = nil
    }

    /// Re-apply session-scoped holds. macOS can drop the IOKit clamshell
    /// override when the power source or network changes (typical of hotspot).
    func reassert() {
        guard assertionHeld || ioConnect != 0 else { return }
        _ = applyClamshellOverride(disableLidSleep: true)
        takeIdleAssertion()
        tryKeepWiFiPowered()
        if didEnableSleepDisabled {
            _ = runSilentSleepDisabled(true)
        }
    }

    func currentStatus() -> KeepAwakeStatus {
        let flag = PowerSnapshot.sleepDisabledFlag()
        return KeepAwakeStatus(
            sleepDisabled: flag == true,
            clamshellOverride: ioConnect != 0,
            assertionHeld: assertionHeld,
            usingAdminSleepDisabled: flag == true,
            message: Self.describe(
                sleepDisabled: flag == true,
                clamshell: ioConnect != 0,
                assertion: assertionHeld,
                adminError: nil
            )
        )
    }

    // MARK: - IOPM assertions (idle sleep, not lid)

    private func takeIdleAssertion() {
        if assertionHeld { return }
        var aid: IOPMAssertionID = 0
        let name = "VibeMode is keeping this Mac awake for coding agents" as CFString
        let kr = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &aid
        )
        if kr == kIOReturnSuccess {
            assertionID = aid
            assertionHeld = true
        }
    }

    private func releaseIdleAssertion() {
        if assertionHeld {
            IOPMAssertionRelease(assertionID)
            assertionHeld = false
            assertionID = 0
        }
    }

    // MARK: - IOKit clamshell (selector 12)

    /// `kPMSetClamshellSleepState` in xnu `RootDomainUserClient`. Input 1 disables
    /// lid-close sleep; 0 restores it. No entitlement, no root.
    @discardableResult
    private func applyClamshellOverride(disableLidSleep: Bool) -> Bool {
        if !ensureIOKitConnection() { return false }
        var inputs: [UInt64] = [disableLidSleep ? 1 : 0]
        var outputCount: UInt32 = 0
        let kr = inputs.withUnsafeBufferPointer { buf -> kern_return_t in
            IOConnectCallScalarMethod(
                ioConnect,
                UInt32(12),
                buf.baseAddress,
                1,
                nil,
                &outputCount
            )
        }
        return kr == KERN_SUCCESS
    }

    private func ensureIOKitConnection() -> Bool {
        if ioConnect != 0 { return true }
        let matching = IOServiceMatching("IOPMrootDomain")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return false }
        ioService = service
        var connect: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self(), 0, &connect)
        guard kr == KERN_SUCCESS else {
            IOObjectRelease(service)
            ioService = 0
            return false
        }
        ioConnect = connect
        return true
    }

    private func closeIOKit() {
        if ioConnect != 0 {
            IOServiceClose(ioConnect)
            ioConnect = 0
        }
        if ioService != 0 {
            IOObjectRelease(ioService)
            ioService = 0
        }
    }

    // MARK: - Wi-Fi

    private func tryKeepWiFiPowered() {
        guard let iface = CWWiFiClient.shared().interface() else { return }
        if iface.powerOn() { return }
        try? iface.setPower(true)
    }

    // MARK: - Restore

    private func releaseEverything(restoreSleepDisabled: Bool) {
        _ = applyClamshellOverride(disableLidSleep: false)
        releaseIdleAssertion()
        closeIOKit()
        if restoreSleepDisabled, didEnableSleepDisabled, snapshot?.sleepDisabled != true {
            do {
                try Privilege.setSleepDisabled(false)
            } catch {
                Privilege.emergencyDisableSleepFlagIfPossible()
            }
        }
        didEnableSleepDisabled = false
        snapshot = nil
    }

    private func runSilentSleepDisabled(_ disabled: Bool) -> Bool {
        let value = disabled ? "1" : "0"
        let sudo = ProcessRunner.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value])
        if sudo.exitCode == 0 { return true }
        let plain = ProcessRunner.run("/usr/bin/pmset", ["-a", "disablesleep", value])
        return plain.exitCode == 0
    }

    private static func describe(sleepDisabled: Bool, clamshell: Bool, assertion: Bool, adminError: String?) -> String {
        var parts: [String] = []
        if sleepDisabled {
            parts.append("SleepDisabled on")
        }
        if clamshell {
            parts.append("lid override on")
        }
        if assertion {
            parts.append("idle assertion on")
        }
        if parts.isEmpty {
            parts.append("could not take a keep-awake hold")
        }
        if let adminError, !sleepDisabled {
            parts.append(adminError)
        }
        return parts.joined(separator: " · ")
    }
}

struct PowerSnapshot: Equatable {
    var sleepDisabled: Bool?
    var raw: String
    var capturedAt: Date

    static func capture() -> PowerSnapshot {
        let result = ProcessRunner.run("/usr/bin/pmset", ["-g"])
        return PowerSnapshot(
            sleepDisabled: parseSleepDisabled(result.stdout),
            raw: result.stdout,
            capturedAt: Date()
        )
    }

    static func sleepDisabledFlag() -> Bool? {
        parseSleepDisabled(ProcessRunner.run("/usr/bin/pmset", ["-g"]).stdout)
    }

    static func parseSleepDisabled(_ text: String) -> Bool? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().contains("sleepdisabled") else { continue }
            if trimmed.contains("1") { return true }
            if trimmed.contains("0") { return false }
        }
        return nil
    }
}
