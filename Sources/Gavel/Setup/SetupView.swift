import SwiftUI

struct SetupView: View {
    @ObservedObject private var state = AppState.shared
    @State private var isInstalling = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Connect Gavel to Claude Code")
                    .font(.title2.bold())
                Text("This will add hooks to ~/.claude/settings.json\nto intercept tool approvals.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 12) {
                Button {
                    install()
                } label: {
                    HStack {
                        if isInstalling { BrailleSpinner() }
                        Text(isInstalling ? "Installing..." : "Connect to Claude Code")
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)

                Button("Cancel", role: .cancel) { dismiss() }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 400)
    }

    private func install() {
        isInstalling = true
        error = nil
        Task {
            do {
                try ClaudeSettingsManager.install(blockApprovals: state.blockApprovals)
                await MainActor.run {
                    state.markSetupComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }
}
