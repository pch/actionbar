import SwiftUI

struct AboutView: View {
    @EnvironmentObject var updater: UpdaterService

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("ActionBar")
                .font(.headline)

            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Website") {
                if let url = URL(string: "https://ptrchm.com/actionbar/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
            .buttonStyle(.link)

            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .font(.caption)
            .disabled(!updater.canCheckForUpdates)
        }
        .padding(16)
    }
}

#Preview {
    AboutView()
        .environmentObject(UpdaterService())
}
