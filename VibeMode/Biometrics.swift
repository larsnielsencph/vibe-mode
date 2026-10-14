import AppKit
import LocalAuthentication

enum Biometrics {
    static var isAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .faceID: return "Face ID"
        default: return "biometrics"
        }
    }

    /// Confirms the user with the Mac's enrolled fingerprint (or other biometrics).
    /// Returns `true` when the setting is off or no biometrics are enrolled.
    @MainActor
    static func confirmSwitch(enabled: Bool, reason: String) async -> Bool {
        guard enabled, isAvailable else { return true }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = ""
        NSApp.activate(ignoringOtherApps: true)
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
