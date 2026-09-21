import SwiftUI

/// The soft gradient + glassy blob backdrop shared by the splash and
/// sign-in screens. Two oversized circles bleeding off the top-right and
/// bottom-left corners, rendered through real Liquid Glass so they pick up
/// refraction/specular highlights instead of being flat blurred gradients.
struct GlassBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.95, blue: 0.90),
                        Color(red: 1.0, green: 0.97, blue: 0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Deliberately not sharing one GlassEffectContainer here:
                // these two blobs are far apart and don't need to visually
                // merge, and a container's own layout algorithm overrides
                // .position() for multiple top-level children.
                Circle()
                    .fill(.clear)
                    .frame(width: size.width * 0.75, height: size.width * 0.75)
                    .glassEffect(.regular.tint(AppTheme.emberRed.opacity(0.5)), in: Circle())
                    .position(x: size.width * 0.92, y: size.height * 0.02)
                    .opacity(0.9)

                Circle()
                    .fill(.clear)
                    .frame(width: size.width * 0.95, height: size.width * 0.95)
                    .glassEffect(.regular.tint(AppTheme.accent.opacity(0.55)), in: Circle())
                    .position(x: size.width * 0.05, y: size.height * 0.88)
                    .opacity(0.9)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    GlassBackdrop()
}
