import SwiftUI

extension View {
    /// Small borderless text button, used for secondary actions throughout the menu.
    func textButtonStyle(_ color: Color = .secondary, font: Font = .caption) -> some View {
        self
            .font(font)
            .buttonStyle(.plain)
            .foregroundStyle(color)
    }
}

struct QuitButton: View {
    var body: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .textButtonStyle()
    }
}
