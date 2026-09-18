import SwiftUI
import SwiftData
import MoneyIQCore

@main
struct MoneyIQApp: App {
    let container = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
