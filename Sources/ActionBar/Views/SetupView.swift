import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

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

    @ViewBuilder
    private var initialView: some View {
        Image(nsImage: MenuBarIcon.image())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 32)

        Text("ActionBar")
            .font(.headline)

        explanation("Monitor your GitHub Actions workflow runs.")

        Button {
            appState.loginWithGitHub()
        } label: {
            Group {
                if appState.isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Login with GitHub")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(appState.isLoggingIn)
        .keyboardShortcut(.defaultAction)

        errorText

        QuitButton()
    }

    // MARK: - Installation Required

    @ViewBuilder
    private var installationView: some View {
        Image(systemName: "puzzlepiece.extension")
            .font(.system(size: 28))
            .foregroundStyle(Color.accentColor)

        Text("Install the App")
            .font(.headline)

        explanation("ActionBar needs to be installed on your GitHub account to access workflow data.")

        Button {
            openURL(GitHubApp.installationURL)
        } label: {
            Text("Install on GitHub")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)

        explanation("After installing, it may take up to a minute for GitHub to reflect the change.")

        Button("Check Again") {
            appState.checkInstallationAndStart()
        }
        .textButtonStyle(.accentColor)
        .disabled(appState.isCheckingInstallation)

        errorText

        Button("Sign Out") {
            appState.signOut()
        }
        .textButtonStyle()

        QuitButton()
    }

    // MARK: - Device Code State

    @ViewBuilder
    private func deviceCodeView(_ code: DeviceCodeResponse) -> some View {
        Text("Enter this code on GitHub:")
            .font(.headline)

        HStack(spacing: 8) {
            Text(code.userCode)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .textSelection(.enabled)

            Button("Copy code", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Copy code")
        }

        explanation("A browser window has opened where you can enter the code above.")

        Button("Open GitHub") {
            if let url = URL(string: code.verificationUri) {
                openURL(url)
            }
        }
        .buttonStyle(.link)

        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for authorization...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button("Cancel") {
            appState.cancelLogin()
        }
        .textButtonStyle()

        QuitButton()
    }

    // MARK: - Shared

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var errorText: some View {
        if let error = appState.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview("Login") {
    SetupView()
        .environment(AppState())
}

#Preview("Device Code") {
    let state = AppState()
    state.deviceCode = DeviceCodeResponse(
        deviceCode: "abc123",
        userCode: "ABCD-1234",
        verificationUri: "https://github.com/login/device",
        interval: 5
    )
    return SetupView()
        .environment(state)
}

#Preview("Installation Required") {
    let state = AppState()
    state.needsInstallation = true
    return SetupView()
        .environment(state)
}
