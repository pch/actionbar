import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var updater: UpdaterService

    private static let websiteURL = URL(string: "https://ptrchm.com/actionbar/")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("ActionBar")
                .font(.headline)

            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("Website", destination: Self.websiteURL)
                .font(.caption)

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
