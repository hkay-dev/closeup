import AppKit
import Foundation

/// Turns on OBS's camera for the user: OBS asks macOS for its camera extension each time it starts, so Setup starts it
/// hidden, macOS shows its own "new camera extension" box, and Setup quits OBS once the camera is on. Nothing in OBS
/// needs a click. Checked with OBS 32.2 on macOS 27 (kata:android-webcam#79fh).
enum OBSSetup {
    /// System Settings > General > Login Items & Extensions > Camera Extensions, with OBS's switch.
    static let cameraExtensionsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
                                         + "?extensionPointIdentifier=com.apple.system_extension.cmio.extension-point")!

    static var configDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("obs-studio", isDirectory: true)
    }

    /// Setup started OBS for its camera and hasn't quit it yet. Main thread only.
    private(set) static var requested = false

    /// Starts OBS in the background so macOS asks about its camera. The first time, OBS's settings are written first,
    /// so it skips its permissions window, its setup wizard and its "really quit?" box.
    static func requestCamera(obs: URL) {
        requested = true
        if DevMode.isOn { DevMode.record("obs", "request camera"); return }
        DispatchQueue.global(qos: .utility).async {
            prepareFirstLaunch()
            DispatchQueue.main.async {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.hides = true
                configuration.arguments = ["--minimize-to-tray"]
                NSWorkspace.shared.openApplication(at: obs, configuration: configuration) { _, error in
                    if let error { NSLog("Couldn't start OBS for its camera: \(error.localizedDescription)") }
                }
            }
        }
    }

    /// macOS shows its camera box only once, so after that the switch is reached here.
    static func openCameraExtensions() {
        if DevMode.isOn { DevMode.record("obs", "open camera extensions"); return }
        NSWorkspace.shared.open(cameraExtensionsURL)
    }

    /// Quits the OBS that requestCamera started, once its camera is on.
    static func quitRequested() {
        guard requested else { return }
        requested = false
        if DevMode.isOn { DevMode.record("obs", "quit"); return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Installer.obsBundleID) { app.terminate() }
    }

    /// Writes OBS's settings only when OBS has never run here; an OBS someone already uses keeps its own.
    /// global.ini: MacOSPermissionsDialogLastShown skips the permissions window. user.ini: FirstRun skips the
    /// Auto-Configuration Wizard (and the mic source it adds), ConfirmOnExit the box that a quit with an output running
    /// shows. SUEnableAutomaticChecks answers Sparkle's "Check for updates automatically?" (asked on OBS's second launch)
    /// with OBS's own default, yes.
    private static func prepareFirstLaunch() {
        let manager = FileManager.default
        let global = configDirectory.appendingPathComponent("global.ini")
        let user = configDirectory.appendingPathComponent("user.ini")
        guard !manager.fileExists(atPath: global.path), !manager.fileExists(atPath: user.path) else { return }
        do {
            try manager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try "[General]\nMacOSPermissionsDialogLastShown=1\n".write(to: global, atomically: true, encoding: .utf8)
            try "[General]\nFirstRun=true\nConfirmOnExit=false\n".write(to: user, atomically: true, encoding: .utf8)
            let domain = Installer.obsBundleID as CFString
            CFPreferencesSetAppValue("SUEnableAutomaticChecks" as CFString, kCFBooleanTrue, domain)
            CFPreferencesAppSynchronize(domain)
        } catch {
            NSLog("Couldn't write OBS's first settings: \(error.localizedDescription)")
        }
    }
}
