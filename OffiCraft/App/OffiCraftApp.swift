import SwiftUI

@main
struct OffiCraftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(session.appearance.colorScheme)
                .tint(OC.accent)
                .task {
                    await session.bootstrap()
                    appDelegate.session = session
                }
        }
    }
}
