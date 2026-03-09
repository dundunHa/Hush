import SwiftUI

struct TypingIndicator: View {
    @State private var dotIndex = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(HushColors.secondaryText)
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotIndex == index ? 1.2 : 0.8)
                    .opacity(dotIndex == index ? 1 : 0.5)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .themeRefreshAware()
    }

    private func startAnimation() {
        guard animationTask == nil else { return }

        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { break }

                withAnimation(.easeInOut(duration: 0.3)) {
                    dotIndex = (dotIndex + 1) % 3
                }
            }
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
    }
}
