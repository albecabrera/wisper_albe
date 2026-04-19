// PopoverView.swift
import SwiftUI
import AppKit

struct PopoverView: View {

    @EnvironmentObject private var sr: SpeechRecognizer
    @State private var justCopied = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            waveformCard
            transcriptSection
            actionBar
        }
        .frame(width: 560)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: – Header

    private var headerBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("WisperBar")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
            }

            Spacer()

            // Language selector – pill style
            HStack(spacing: 3) {
                ForEach(DictationLanguage.allCases) { lang in
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                            sr.selectedLanguage = lang
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(lang.flag)
                                .font(.system(size: 16))
                            if sr.selectedLanguage == lang {
                                Text(lang.shortName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            sr.selectedLanguage == lang
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(sr.selectedLanguage == lang ? 1.0 : 0.40)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: sr.selectedLanguage)
                    .help(lang.displayName)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: – Waveform card

    private var waveformCard: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background that reacts to recording state
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: sr.recordingState.isRecording
                                ? [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.03)]
                                : [Color(.controlBackgroundColor).opacity(0.55), Color(.controlBackgroundColor).opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                sr.recordingState.isRecording
                                    ? Color.accentColor.opacity(0.30)
                                    : Color(.separatorColor).opacity(0.5),
                                lineWidth: 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.4), value: sr.recordingState.isRecording)

                VStack(spacing: 0) {
                    // Waveform
                    ZStack {
                        if sr.recordingState.isRecording {
                            WaveformView(levels: sr.audioLevels)
                                .transition(.opacity)
                        } else {
                            IdleWaveformView()
                                .transition(.opacity)
                        }
                    }
                    .frame(height: 90)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .animation(.easeInOut(duration: 0.25), value: sr.recordingState.isRecording)

                    // Status strip inside the card
                    HStack(spacing: 8) {
                        if sr.recordingState.isRecording {
                            RecordingDotView()
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(statusDotColor)
                                .frame(width: 7, height: 7)
                                .transition(.scale.combined(with: .opacity))
                        }

                        Text(statusText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(sr.recordingState.isRecording ? .primary : .secondary)
                            .lineLimit(1)
                            .animation(.easeInOut(duration: 0.2), value: statusText)

                        Spacer()

                        if sr.recordingState.isRecording {
                            RecordingTimerView()
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 10))
                                Text("fn ⇧")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(Color(.tertiaryLabelColor))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(.controlBackgroundColor).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sr.recordingState.isRecording)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: – Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transkription")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.1)

                Spacer()

                if !sr.transcript.isEmpty {
                    Text("\(sr.transcript.split(separator: " ").count) Wörter · \(sr.transcript.count) Zeichen")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(.tertiaryLabelColor))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                sr.recordingState.isRecording
                                    ? Color.accentColor.opacity(0.45)
                                    : Color(.separatorColor),
                                lineWidth: sr.recordingState.isRecording ? 1.5 : 1
                            )
                            .animation(.easeInOut(duration: 0.3), value: sr.recordingState.isRecording)
                    )

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if !sr.transcript.isEmpty {
                                Text(sr.transcript)
                                    .font(.system(size: 14))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity)
                            }

                            if !sr.interimTranscript.isEmpty {
                                Text(sr.interimTranscript)
                                    .font(.system(size: 14))
                                    .lineSpacing(4)
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity)
                            }

                            if sr.transcript.isEmpty && sr.interimTranscript.isEmpty {
                                Text("Sprich los – dein Text erscheint hier in Echtzeit…")
                                    .font(.system(size: 14))
                                    .lineSpacing(4)
                                    .foregroundStyle(Color(.placeholderTextColor))
                            }

                            // Scroll anchor
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(14)
                        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: sr.transcript)
                    }
                    .frame(maxHeight: 210)
                    .onChange(of: sr.interimTranscript) { _ in
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                    .onChange(of: sr.transcript) { _ in
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                }
            }
            .padding(.horizontal, 16)

            // Error message
            if case .error(let msg) = sr.recordingState {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: sr.recordingState)
    }

    // MARK: – Action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.top, 14)

            HStack(spacing: 10) {
                // Primary: Record / Stop – wide, prominent
                Button {
                    sr.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: sr.recordingState.isRecording
                              ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(sr.recordingState.isRecording ? "Stopp" : "Aufnehmen")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(sr.recordingState.isRecording ? .red : .accentColor)
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: sr.recordingState.isRecording)

                // Copy
                Button {
                    sr.copyToClipboard()
                    withAnimation(.spring(response: 0.2)) { justCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { justCopied = false }
                    }
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .tint(justCopied ? .green : nil)
                .disabled(sr.transcript.isEmpty)
                .help(justCopied ? "Kopiert!" : "In Zwischenablage kopieren")
                .animation(.spring(response: 0.2), value: justCopied)

                // Paste to active app
                Button {
                    NotificationCenter.default.post(name: .wbReadyToPaste, object: nil)
                } label: {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(sr.transcript.isEmpty)
                .help("In aktive App einfügen (Cmd+V)")

                // Clear
                Button {
                    withAnimation(.spring(response: 0.3)) { sr.clearTranscript() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(.tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .disabled(sr.transcript.isEmpty && sr.interimTranscript.isEmpty)
                .help("Transkript leeren")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    // MARK: – Helpers

    private var statusText: String {
        switch sr.recordingState {
        case .idle:
            return sr.transcript.isEmpty
                ? "Bereit – fn+Shift oder Button drücken"
                : "Fertig  ·  \(sr.selectedLanguage.flag) \(sr.selectedLanguage.displayName)"
        case .requestingPermission:
            return "Berechtigungen werden angefordert…"
        case .recording:
            return "\(sr.selectedLanguage.flag) \(sr.selectedLanguage.displayName) · Aufnahme läuft…"
        case .error:
            return "Fehler – Details unten"
        }
    }

    private var statusDotColor: Color {
        switch sr.recordingState {
        case .idle:                 return Color(.tertiaryLabelColor)
        case .requestingPermission: return .orange
        case .recording:            return .red
        case .error:                return .orange
        }
    }
}

#Preview {
    PopoverView()
        .environmentObject(SpeechRecognizer())
        .frame(width: 560)
}
