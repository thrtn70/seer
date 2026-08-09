import AppKit
import Sparkle

/// Sparkle auto-update (§9 / Phase 13). Owns the updater and performs the accessory-app
/// activation dance: an LSUIElement app has no active presentation context, so Sparkle's
/// update window would appear unfocused or behind other apps unless the app temporarily
/// becomes `.regular` for the duration of the update session.
///
/// Deliberately NOT wired to UNUserNotification: that would add a notification-authorization
/// prompt, and a menu-bar app that is always running shows the update window fine via the
/// activation flip alone. Revisit only if scheduled updates prove too easy to miss.
/// `@preconcurrency` on the conformance: `SPUStandardUserDriver` is declared
/// `NS_SWIFT_UI_ACTOR` (main-actor) and is what invokes these callbacks, but
/// `SPUStandardUserDriverDelegate` itself carries no isolation annotation — so the isolation
/// is real yet invisible to the compiler. Without this, the conformance warns (an error under
/// the Swift 6 language mode); with it, isolation is enforced at runtime instead.
@MainActor
final class UpdaterController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    /// Assigned immediately after `super.init()` — Sparkle takes its delegates at construction
    /// and `self` isn't available before then. Standard Cocoa two-phase init; every use site
    /// runs after `init` returns. (Not on any panic/keystroke path, unlike the Settings panes.)
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        // startingUpdater: false so the updater isn't started before `self` is wired as the
        // user-driver delegate; started explicitly on the next line.
        updaterController = SPUStandardUpdaterController(startingUpdater: false,
                                                        updaterDelegate: nil,
                                                        userDriverDelegate: self)
        do {
            // `-startUpdater:` is imported into Swift as `start()`.
            try updaterController.updater.start()
        } catch {
            // Never fatal: a failed updater must not stop Seer from suggesting.
            FileHandle.standardError.write(Data(
                "[seer] Sparkle updater failed to start: \(error)\n".utf8))
        }
    }

    /// Target/action for the menu item. Handed to MenuController as an opaque pair so
    /// MenuController never imports Sparkle. Sparkle's own NSMenuValidation on this target
    /// enables/disables the item from `SPUUpdater.canCheckForUpdates` — no manual validation.
    var checkForUpdatesTarget: AnyObject { updaterController }
    var checkForUpdatesAction: Selector { #selector(SPUStandardUpdaterController.checkForUpdates(_:)) }

    // MARK: - SPUStandardUserDriverDelegate (accessory activation dance)

    /// Required for dockless apps, or Sparkle warns that a background app schedules update
    /// checks without implementing gentle reminders. Note this does NOT by itself stop a
    /// scheduled update from taking focus — the activation flip below is unconditional, which
    /// is deliberate: with no Dock icon and no notification, an alert placed behind other
    /// windows would be undiscoverable. Same pattern OnboardingWindow/SettingsWindow use.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        // Become foregroundable so the update window can show and take focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Back to menu-bar-only.
        NSApp.setActivationPolicy(.accessory)
    }
}
