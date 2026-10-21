import SwiftUI

struct StatusDotView: View {
    let status: RunStatus

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color(nsColor: status.color))
            .frame(width: 8, height: 8)
            .opacity(isPulsing && status == .running ? 0.4 : 1.0)
            .animation(
                status == .running
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: status, initial: true) {
                isPulsing = status == .running
            }
    }
}

#Preview("Success") {
    StatusDotView(status: .success)
}

#Preview("Failure") {
    StatusDotView(status: .failure)
}

#Preview("Running") {
    StatusDotView(status: .running)
}

#Preview("Queued") {
    StatusDotView(status: .queued)
}

#Preview("Cancelled") {
    StatusDotView(status: .cancelled)
}

#Preview("Unknown") {
    StatusDotView(status: .unknown)
}
