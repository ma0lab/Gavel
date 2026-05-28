import SwiftUI

@main
struct GavelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // AppDelegate manages the status item and all windows directly
        Settings { EmptyView() }
    }
}
