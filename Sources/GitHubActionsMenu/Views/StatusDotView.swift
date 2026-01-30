import SwiftUI

struct StatusDotView: View {
    let status: RunStatus

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isPulsing && status == .running ? 0.4 : 1.0)
            .animation(
                status == .running
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if status == .running {
                    isPulsing = true
                }
            }
            .onChange(of: status) { newStatus in
                isPulsing = newStatus == .running
            }
    }

    private var color: Color {
        switch status {
        case .success: return .green
        case .failure: return .red
        case .running: return .orange
        case .queued: return .yellow
        case .cancelled: return .gray
        case .unknown: return .gray
        }
    }
}
