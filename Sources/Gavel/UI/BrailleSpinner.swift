import SwiftUI

struct BrailleSpinner: View {
    private static let frames: [Character] = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    @State private var index = 0
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(Self.frames[index]))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in
                index = (index + 1) % Self.frames.count
            }
    }
}
