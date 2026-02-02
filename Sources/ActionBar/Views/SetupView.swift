import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            if appState.needsInstallation {
                installationView
            } else if let code = appState.deviceCode {
                deviceCodeView(code)
            } else {
                initialView
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    // MARK: - Initial State

    private var initialView: some View {
        Group {
            Image(nsImage: GitHubIcon.makeMenuBarIcon())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            Text("Action Bar for GitHub")
                .font(.headline)

            Text("Monitor your GitHub Actions workflow runs.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { appState.loginWithGitHub() }) {
                if appState.isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Login with GitHub")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoggingIn)
            .keyboardShortcut(.defaultAction)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Installation Required

    private var installationView: some View {
        Group {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)

            Text("Install the App")
                .font(.headline)

            Text("Action Bar needs to be installed on your GitHub account to access workflow data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { appState.openInstallationPage() }) {
                Text("Install on GitHub")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button("Check Again") {
                appState.checkInstallationAndStart()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Sign Out") {
                appState.signOut()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Device Code State

    private func deviceCodeView(_ code: DeviceCodeResponse) -> some View {
        Group {
            Text("Enter this code on GitHub:")
                .font(.headline)

            HStack(spacing: 8) {
                Text(code.userCode)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }

            Text("A browser window has opened where you can enter the code above.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                if let url = URL(string: code.verificationUri) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Open GitHub")
            }
            .buttonStyle(.link)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for authorization...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Cancel") {
                appState.cancelLogin()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
}
