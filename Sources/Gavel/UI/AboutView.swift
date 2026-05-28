import SwiftUI

private let helpURL    = URL(string: "https://github.com/niau/claudebar/issues")!
private let contactURL = URL(string: "mailto:hello@niau.app")!

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 16, x: 0, y: 6)
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 6) {
                    Text("Gavel")
                        .font(.system(size: 20, weight: .bold))
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.06), in: Capsule())
                }
            }

            Spacer().frame(height: 40)
            Divider().padding(.horizontal, 60)
            Spacer().frame(height: 32)

            HStack(spacing: 16) {
                aboutLink(url: helpURL,    label: "Help",    icon: "questionmark.circle")
                aboutLink(url: contactURL, label: "Contact", icon: "envelope")
            }
            .frame(maxWidth: .infinity)

            Spacer()

            Text("© 2025 niau")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func aboutLink(url: URL, label: String, icon: String) -> some View {
        Link(destination: url) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}
