import SwiftUI

@main
struct ClaudeNotifyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = NotificationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    appDelegate.store = store
                    store.loadLocal()
                    await store.refreshFromServer()
                }
        }
    }
}
