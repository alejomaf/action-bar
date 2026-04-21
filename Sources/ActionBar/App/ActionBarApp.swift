import AppKit
import SwiftUI

@main
struct ActionBarApp: App {
    private enum WindowID {
        static let settings = "settings"
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            StatusBarLabel(summary: store.summary, isRefreshing: store.isRefreshing)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: WindowID.settings) {
            SettingsView(store: store)
        }
        .defaultSize(width: 520, height: 400)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
