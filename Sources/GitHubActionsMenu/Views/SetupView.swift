import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text("GitHub Actions Menu")
                .font(.headline)

            Text("Enter a GitHub personal access token\nwith **repo** and **workflow** scopes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            SecureField("ghp_...", text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit { validate() }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: validate) {
                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.isEmpty || isValidating)
            .keyboardShortcut(.defaultAction)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 280)
    }

    private func validate() {
        guard !token.isEmpty else { return }
        isValidating = true
        errorMessage = nil

        Task {
            do {
                try await appState.authenticate(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                errorMessage = error.localizedDescription
            }
            isValidating = false
        }
    }
}
