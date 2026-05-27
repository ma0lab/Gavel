import SwiftUI

// MARK: - 録音・変換中インジケーター

struct VoiceIndicatorView: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let audioLevel: Float
    var errorMessage: String? = nil

    var body: some View {
        if let error = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
        } else if isRecording || isTranscribing {
            VStack(spacing: 12) {
                if isRecording {
                    HStack(spacing: 3) {
                        ForEach(0..<15, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(waveColor(index: i))
                                .frame(width: 4, height: waveHeight(index: i))
                        }
                    }
                    .frame(height: 30)
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("録音中")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("変換中...")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
        }
    }

    private func waveColor(index: Int) -> Color {
        Float(index) / 15 < audioLevel ? .white : .white.opacity(0.3)
    }

    private func waveHeight(index: Int) -> CGFloat {
        let base: CGFloat = CGFloat(30 - abs(index - 7) * 3)
        return max(4, base * CGFloat(audioLevel))
    }
}

// MARK: - テキスト確認・編集パネル

struct VoiceConfirmView: View {
    @Binding var editingText: String
    let originalText: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool
    private var isEdited: Bool { editingText != originalText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("音声入力の確認")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("編集して確定、またはそのまま確定")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().background(.white.opacity(0.12))

            TextEditor(text: $editingText)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .focused($isFocused)
                .frame(minHeight: 60, maxHeight: 180)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().background(.white.opacity(0.12))

            HStack(spacing: 10) {
                Button { onConfirm(editingText) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isEdited ? "pencil.and.sparkles" : "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isEdited ? "編集して確定" : "確定")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button { onCancel() } label: {
                    Text("キャンセル")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    KeyHintTag(key: "⌘↩", label: "確定")
                    KeyHintTag(key: "Esc", label: "キャンセル")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
}

private struct KeyHintTag: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}
