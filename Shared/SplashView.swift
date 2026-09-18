import SwiftUI

struct SplashView: View {
    @State private var logoAppeared = false

    var body: some View {
        ZStack {
            GlassBackdrop()

            VStack(spacing: 18) {
                MLogoView(size: 150)
                    .scaleEffect(logoAppeared ? 1 : 0.8)
                    .opacity(logoAppeared ? 1 : 0)

                VStack(spacing: 6) {
                    (
                        Text("Money ")
                            .foregroundStyle(.primary)
                        + Text("IQ")
                            .foregroundStyle(Color.accentColor)
                    )
                    .font(.system(size: 40, weight: .heavy, design: .rounded))

                    Text("Know More    Do Better")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }
                .opacity(logoAppeared ? 1 : 0)
                .offset(y: logoAppeared ? 0 : 8)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3)) {
                logoAppeared = true
            }
        }
    }
}

#Preview {
    SplashView()
}
