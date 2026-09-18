#if os(iOS)
import UIKit

enum UIApplicationHelper {
    @MainActor
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif

#if os(macOS)
import AppKit

enum NSApplicationHelper {
    @MainActor
    static var keyWindow: NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
    }
}
#endif
