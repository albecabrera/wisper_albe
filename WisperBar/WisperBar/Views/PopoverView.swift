// PopoverView.swift
// Haupt-UI des Popovers – zeigt Wellenform, Transkript und Steuerelemente.
import SwiftUI
import AppKit

struct PopoverView: View {

    @EnvironmentObject private var sr: SpeechRecognizer
    @State private var justCopied = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            waveformSection
            Divider()
            transcriptSection
            Divider()
            actionBar
        }
        .frame(width: 400)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: – Header (Titel + Sprachauswahl)

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Logo + Name
            HStack(spacing: 6) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("WisperBar")
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            // Sprach-Flags
            HStack(spacing: 2) {
                ForEach(DictationLanguage.allCases) { lang in
                    Button {
                        sr.selectedLanguage = lang
                    } label: {
                        Text(lang.flag)
                            .font(.system(size: 20))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .opacity(sr.selectedLanguage == lang ? 1.0 : 0.3)
                    .scaleEffect(sr.selectedLanguage == lang ? 1.05 : 1.0)
                    .animation(.spring(response: 0.2), value: sr.selectedLanguage)
                    .help(lang.displayName)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: – Wellenform-Bereich

    private var waveformSection: some View {
        VStack(spacing: 8) {
            // Wellenform
            ZStack {
                if sr.recordingState.isRecording {
                    WaveformView(levels: sr.audioLevels)
                } else {
                    IdleWaveformView()
                }
            }
            .frame(height: 68)
            .padding(.horizontal, 16)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Status-Zeile
            HStack(spacing: 6) {
                // Aufnahme-Indikator
                if sr.recordingState.isRecording {
                    RecordingDotView()
                } else {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                }

                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if sr.recordingState.isRecording {
                    RecordingTimerView()
                } else {
                    Text("⌘⇧D")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabelColor))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }

    // MARK: – Transkript-Bereich

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transkription")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if !sr.transcript.isEmpty {
                    Text("\(sr.transcript.split(separator: " ").count) Wörter")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabelColor))
                }
            }

            // Haupt-Textfeld
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                sr.recordingState.isRecording
                                    ? Color.accentColor.opacity(0.5)
                                    : Color(.separatorColor),
                                lineWidth: 1
                            )
                    )

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Gesicherter Text
                        if !sr.transcript.isEmpty {
                            Text(sr.transcript)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Vorläufiger Text (kursiv, gedämpft)
                        if !sr.interimTranscript.isEmpty {
                            Text(sr.interimTranscript)
                                .font(.system(size: 14))
                                .italic()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Platzhalter
                        if sr.transcript.isEmpty && sr.interimTranscript.isEmpty {
                            Text("Dein Text erscheint hier…")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.placeholderTextColor))
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 150)
            }

            // Fehlermeldung
            if case .error(let msg) = sr.recordingState {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
    }

    // MARK: – Aktionsleiste

    private var actionBar: some View {
        HStack(spacing: 8) {
            // Hauptbutton: Aufnahme starten / stoppen
            Button {
                sr.toggle()
            } label: {
                Label(
                    sr.recordingState.isRecording ? "Stopp" : "Aufnehmen",
                    systemImage: sr.recordingState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(sr.recordingState.isRecording ? .red : .accentColor)
            .controlSize(.regular)
            .keyboardShortcut(.space, modifiers: [])

            Spacer()

            // Kopieren
            Button {
                sr.copyToClipboard()
                withAnimation { justCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation { justCopied = false }
                }
            } label: {
                Label(
                    justCopied ? "Kopiert!" : "Kopieren",
                    systemImage: justCopied ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(sr.transcript.isEmpty)
            .tint(justCopied ? .green : nil)

            // Einfügen
            Button {
                sr.insertAtCursor()
            } label: {
                Label("Einfügen", systemImage: "arrow.right.doc.on.clipboard")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(sr.transcript.isEmpty)
            .help("Text in das aktive Textfeld einfügen (erfordert Bedienungshilfen-Zugriff)")

            // Löschen
            Button {
                withAnimation { sr.clearTranscript() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .disabled(sr.transcript.isEmpty && sr.interimTranscript.isEmpty)
            .help("Transkript leeren")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: – Hilfseigenschaften

    private var statusText: String {
        switch sr.recordingState {
        case .idle:
            return sr.transcript.isEmpty
                ? "Bereit – Shortcut oder Button drücken"
                : "Fertig – \(sr.selectedLanguage.flag) \(sr.selectedLanguage.displayName)"
        case .requestingPermission:
            return "Berechtigungen werden angefordert…"
        case .recording:
            return "Aufnahme läuft (\(sr.selectedLanguage.flag) \(sr.selectedLanguage.displayName))…"
        case .error:
            return "Fehler aufgetreten"
        }
    }

    private var statusDotColor: Color {
        switch sr.recordingState {
        case .idle:                    return Color(.tertiaryLabelColor)
        case .requestingPermission:    return .orange
        case .recording:               return .red
        case .error:                   return .orange
        }
    }
}

// MARK: – Vorschau

#Preview {
    PopoverView()
        .environmentObject(SpeechRecognizer())
        .frame(width: 400)
}
