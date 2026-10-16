// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import GleeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Glee intentionally lives in the menu bar, with no persistent Dock icon.
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(model: model)
        NSApp.mainMenu = ApplicationMenu.make(target: self, settingsAction: #selector(openSettings))
        model.updates.start()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Respect an explicit sleep or lid-close. Do not restart on wake.
            MainActor.assumeIsolated { self?.model.handleSystemSleep() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.session.refresh() }
        }
        if LaunchPresentation.shouldShowPopover(for: NSAppleEventManager.shared().currentAppleEvent) {
            // Every manual launch opens the status item, including after activation.
            // Login and service launches leave the menu bar quiet.
            DispatchQueue.main.async { [weak self] in self?.menuBar?.show() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.show()
        // Reopening always stays attached to the existing status item.
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.closedLid.refresh()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    @objc private func openSettings() {
        model.showSettings(.general)
        menuBar?.show()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Recheck at the actual termination boundary, including races with
        // helper setup or an outstanding sleep-restoration operation.
        if model.updates.isInstalling, model.updateSafetyPolicy.blockingReason != nil {
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.stop()
        model.shutdown()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
