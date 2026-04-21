import AppKit
import SwiftUI

@main
struct ActionBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            StatusBarLabel(summary: store.summary, isRefreshing: store.isRefreshing)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
