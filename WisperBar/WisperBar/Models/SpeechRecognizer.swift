// SpeechRecognizer.swift
// Kapselt die gesamte Sprach- und Audio-Logik.
// NSObject-Subklasse wegen SFSpeechRecognizerDelegate (erfordert NSObjectProtocol).
import Foundation
import Speech
import AVFoundation
import AppKit

// MARK: – Aufnahmestatus

enum RecordingState: Equatable {
    case idle
    case requestingPermission
    case recording
    case error(String)

    var isRecording: Bool { self == .recording }
}

// MARK: – Sprachauswahl

enum DictationLanguage: String, CaseIterable, Identifiable {
    case german  = "de-DE"
    case english = "en-US"
    case spanish = "es-ES"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .german:  return "Deutsch"
        case .english: return "English"
        case .spanish: return "Español"
        }
    }

    var flag: String {
        switch self {
        case .german:  return "🇩🇪"
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        }
    }

    var shortName: String {
        switch self {
        case .german:  return "DE"
        case .english: return "EN"
        case .spanish: return "ES"
        }
    }
}

// MARK: – SpeechRecognizer

final class SpeechRecognizer: NSObject, ObservableObject {

    // MARK: Veröffentlichte Zustände (immer auf Main-Thread schreiben)

    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var interimTranscript: String = ""
    @Published private(set) var audioLevels: [Float] = Array(repeating: 0, count: 32)
    @Published var selectedLanguage: DictationLanguage = .german {
        didSet { rebuildRecognizer() }
    }

    // MARK: Private Eigenschaften

    private var sfRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let barCount = 32

    /// Flag: Session wurde absichtlich beendet → Callbacks ignorieren
    private var isSessionActive = false

    // MARK: – Init

    override init() {
        super.init()
        rebuildRecognizer()
    }

    // MARK: – Öffentliche API

    /// Aufnahme starten oder stoppen (Toggle)
    func toggle() {
        if recordingState.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard recordingState == .idle else { return }
        recordingState = .requestingPermission

        requestPermissions { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                if granted {
                    self.beginSession()
                } else {
                    self.recordingState = .error(
                        "Mikrofon- oder Spracherkennungs-Zugriff verweigert.\n" +
                        "Systemeinstellungen → Datenschutz → Mikrofon / Spracherkennung"
                    )
                }
            }
        }
    }

    /// Aufnahme stoppen und Text sichern. Paste wird via AppDelegate koordiniert,
    /// damit das Popover zuerst geschlossen wird und die Hintergrund-App den Fokus bekommt.
    func stopRecording(autoPaste: Bool = true) {
        guard recordingState.isRecording else { return }

        if !interimTranscript.isEmpty {
            let text = normalizeText(interimTranscript.trimmingCharacters(in: CharacterSet(charactersIn: " \t")))
            if !text.isEmpty {
                let sep = transcript.isEmpty || transcript.hasSuffix("\n") ? "" : " "
                transcript += sep + text
            }
            interimTranscript = ""
        }

        endSession()
        recordingState = .idle

        if !transcript.isEmpty {
            copyToClipboard()
            if autoPaste {
                NotificationCenter.default.post(name: .wbReadyToPaste, object: nil)
            }
        }
    }

    /// Öffentliche Methode: Text in aktives Textfeld einfügen (Cmd+V).
    func pasteToActiveApp() {
        copyToClipboard()
        simulatePaste()
    }

    func clearTranscript() {
        transcript = ""
        interimTranscript = ""
        if case .error = recordingState { recordingState = .idle }
    }

    func copyToClipboard() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    func insertAtCursor() {
        guard !transcript.isEmpty else { return }
        NotificationCenter.default.post(name: .wbReadyToPaste, object: nil)
    }

    // MARK: – Sprachmodell neu aufbauen

    private func rebuildRecognizer() {
        let wasRecording = recordingState.isRecording
        if wasRecording { stopRecording() }
        sfRecognizer = SFSpeechRecognizer(locale: Locale(identifier: selectedLanguage.rawValue))
        sfRecognizer?.delegate = self
        if wasRecording { startRecording() }
    }

    // MARK: – Berechtigungen

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { completion(false); return }
            AVCaptureDevice.requestAccess(for: .audio) { completion($0) }
        }
    }

    // MARK: – Aufnahmesitzung

    private func beginSession() {
        tearDownAudioStack()

        let inputNode = audioEngine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if #available(macOS 13, *) {
            // On-Device bevorzugen: läuft komplett lokal, kein Internet, keine Kosten.
            // Falls die Sprache kein lokales Modell hat, fällt Apple automatisch zurück.
            request.requiresOnDeviceRecognition = sfRecognizer?.supportsOnDeviceRecognition == true
        }

        recognitionRequest = request
        isSessionActive = true

        recognitionTask = sfRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            DispatchQueue.main.async {
                guard self.isSessionActive else { return }

                // ── Ergebnisse verarbeiten ────────────────────────────────────
                if let result {
                    let rawText = result.bestTranscription.formattedString
                    let text = self.normalizeText(rawText)

                    if result.isFinal {
                        // Actualizar interim con el mejor texto disponible antes
                        // de que restartSession() lo vuelque a transcript.
                        let finalHasLetters = text.rangeOfCharacter(from: .letters) != nil
                        if !finalHasLetters && !self.interimTranscript.isEmpty {
                            // Apple devolvió solo puntuación o salto de párrafo:
                            // anexar al interim. No trimear \n para preservar Absatz.
                            let trimSet = CharacterSet(charactersIn: " \t")
                            self.interimTranscript += text.trimmingCharacters(in: trimSet)
                        } else if text.count >= self.interimTranscript.count {
                            self.interimTranscript = text
                        }
                        // restartSession() vuelca interimTranscript → transcript
                        self.restartSession()
                        return
                    } else {
                        if text.rangeOfCharacter(from: .letters) != nil {
                            // Detectar reset de contexto de Apple: ocurre con "Komma" cuando
                            // Apple inserta "," y reinicia su contexto interno sin disparar
                            // isFinal. El siguiente no-final arranca desde cero (más corto)
                            // y sobreescribiría las palabras anteriores.
                            // Si el interim termina en puntuación O salto de párrafo (\n)
                            // y el nuevo texto es más corto → Apple reseteó su contexto;
                            // hacer commit del interim primero para no perder palabras.
                            let interimEndsPunct = self.interimTranscript.last
                                .map { ".,!?:;\n".contains($0) } ?? false
                            if interimEndsPunct && text.count < self.interimTranscript.count {
                                let sep = self.transcript.isEmpty || self.transcript.hasSuffix("\n") ? "" : " "
                                self.transcript += sep + self.interimTranscript
                                self.interimTranscript = ""
                            }
                            self.interimTranscript = text
                        } else {
                            // Solo puntuación o salto de párrafo: anexar, no reemplazar.
                            // Trimear solo espacios/tabs, NO newlines (Absatz → "\n\n").
                            let trimSet = CharacterSet(charactersIn: " \t")
                            self.interimTranscript += text.trimmingCharacters(in: trimSet)
                        }
                    }
                }

                // ── Fehlerbehandlung ──────────────────────────────────────────
                if let error = error as NSError? {
                    // restartSession() se encarga de volcar interimTranscript.
                    if error.domain == "kAFAssistantErrorDomain" {
                        self.restartSession()
                        return
                    }
                    let benignCodes: Set<Int> = [203, 209, -999]
                    let isBenign = benignCodes.contains(error.code) ||
                                   error.localizedDescription.lowercased().contains("cancel")
                    if isBenign {
                        self.restartSession()
                    } else {
                        self.recordingState = .error("Spracherkennungsfehler: \(error.localizedDescription)")
                        self.endSession()
                    }
                }
            }
        }

        // Audio-Tap: Samples an Erkennung + Visualisierung weiterleiten
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.processAudioBuffer(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.recordingState = .recording
                self.interimTranscript = ""
            }
        } catch {
            DispatchQueue.main.async {
                self.recordingState = .error("Audio-Engine Fehler: \(error.localizedDescription)")
            }
            endSession()
        }
    }

    /// Startet nur die Erkennungs-Task neu, ohne den Aufnahmezustand zu ändern.
    /// Wird nach Apple-Timeouts, Server-Fehlern und finalen Ergebnissen aufgerufen.
    private func restartSession() {
        guard isSessionActive else { return }

        // Cerrar el flag ANTES de cancelar para que el callback de cancelación
        // encuentre isSessionActive=false y salga inmediatamente, evitando
        // la cascada de reinicios que corrompía el estado.
        isSessionActive = false

        // Volcar todo interim pendiente antes de destruir la sesión.
        // No añadir espacio si el transcript termina en salto de párrafo.
        if !interimTranscript.isEmpty {
            let sep = transcript.isEmpty || transcript.hasSuffix("\n") ? "" : " "
            transcript += sep + interimTranscript
            interimTranscript = ""
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask   = nil

        // Usar recordingState para saber si el usuario sigue grabando,
        // ya que isSessionActive está temporalmente en false.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.recordingState.isRecording else { return }
            self.beginSession()   // beginSession pone isSessionActive=true
        }
    }

    private func endSession() {
        // Flag zuerst setzen – verhindert dass spätere Callbacks feuern
        isSessionActive = false
        tearDownAudioStack()

        DispatchQueue.main.async {
            self.audioLevels = Array(repeating: 0, count: self.barCount)
            self.interimTranscript = ""
        }
    }

    private func tearDownAudioStack() {
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask   = nil
    }

    // MARK: – Audio-Visualisierung (RMS pro Balken)

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samplesPerBar = max(1, frameLength / barCount)
        var levels = [Float](repeating: 0, count: barCount)

        for bar in 0..<barCount {
            let start = bar * samplesPerBar
            let end   = min(start + samplesPerBar, frameLength)
            var sum: Float = 0
            for i in start..<end { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(end - start))
            levels[bar] = min(rms * 25.0, 1.0)
        }

        DispatchQueue.main.async { self.audioLevels = levels }
    }

    // MARK: – Textnormalisierung

    private func normalizeText(_ input: String) -> String {
        var text = input

        // Phrasen zuerst, damit kürzere Muster nicht zuerst greifen
        let replacements: [(pattern: String, replacement: String)] = [
            // ── English (phrases first) ────────────────────────────────────
            (#"\s*\bnew\s+paragraph\b\s*"#,              "\n\n"),
            (#"\s*\bparagraph\s+break\b\s*"#,            "\n\n"),
            (#"\s*\bexclamation\s+(mark|point)\b\s*"#,   "!"),
            (#"\s*\bquestion\s+mark\b\s*"#,              "?"),
            (#"\s*\bfull\s+stop\b\s*"#,                  "."),
            (#"\s*\bnew\s+line\b\s*"#,                   "\n"),
            (#"\s*\bline\s+break\b\s*"#,                 "\n"),
            // ── Español (frases) ───────────────────────────────────────────
            (#"\s*\bpunto y aparte\b\s*"#,               "\n\n"),
            (#"\s*\bpunto y coma\b\s*"#,                 ";"),
            (#"\s*\bsigno de exclamaci[oó]n\b\s*"#,      "!"),
            (#"\s*\bsigno de interrogaci[oó]n\b\s*"#,    "?"),
            (#"\s*\bdos puntos\b\s*"#,                   ":"),
            (#"\s*\bnueva l[ií]nea\b\s*"#,               "\n"),
            // ── Deutsch ────────────────────────────────────────────────────
            (#"\s*\b[Aa]bsatz\b\s*"#,                    "\n\n"),
            (#"\s*\b[Nn]eue\s+[Zz]eile\b\s*"#,           "\n"),
            (#"\s*\b[Zz]eilenumbruch\b\s*"#,              "\n"),
            (#"\s*\b[Kk]omma\b\s*"#,                     ","),
            (#"\s*\b[Pp]unkt\b\s*"#,                     "."),
            (#"\s*\b[Aa]usrufezeichen\b\s*"#,             "!"),
            (#"\s*\b[Ff]ragezeichen\b\s*"#,               "?"),
            (#"\s*\b[Dd]oppelpunkt\b\s*"#,                ":"),
            (#"\s*\b[Ss]emikolon\b\s*"#,                  ";"),
            (#"\s*\b[Ss]trichpunkt\b\s*"#,                ";"),
            (#"\s*\b[Bb]indestrich\b\s*"#,                "-"),
            // ── English (single words) ─────────────────────────────────────
            (#"\s*\b[Ss]emicolon\b\s*"#,                 ";"),
            (#"\s*\b[Cc]olon\b\s*"#,                     ":"),
            (#"\s*\b[Pp]eriod\b\s*"#,                    "."),
            (#"\s*\b[Hh]yphen\b\s*"#,                    "-"),
            (#"\s*\b[Dd]ash\b\s*"#,                      "-"),
            (#"\s*\b[Cc]omma\b\s*"#,                     ","),
            // ── Español (palabras simples) ─────────────────────────────────
            (#"\s*\bcoma\b\s*"#,                          ","),
            (#"\s*\bpunto\b\s*"#,                         "."),
            (#"\s*\bgu[ií][oó]n\b\s*"#,                  "-"),
        ]

        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
        }

        // Leerzeichen vor Satzzeichen entfernen
        for p in [".", ",", "!", "?", ":", ";"] {
            text = text.replacingOccurrences(of: " \(p)", with: p)
        }

        // Doppelte Satzzeichen auf eins reduzieren
        let dedup: [(String, String)] = [
            (#",+"#, ","), (#"\.+"#, "."), (#"!+"#, "!"),
            (#"\?+"#, "?"), (#":+"#, ":"), (#";+"#, ";"),
        ]
        for (pattern, replacement) in dedup {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
        }

        // Capitalizar tras punto/exclamación/interrogación dentro del chunk
        var capitalized = ""
        var pendingCap = false
        for ch in text {
            if pendingCap && ch.isLetter {
                capitalized.append(contentsOf: ch.uppercased())
                pendingCap = false
            } else {
                capitalized.append(ch)
                if ".!?".contains(ch)   { pendingCap = true }
                else if ch.isWhitespace  { /* mantener estado */ }
                else                     { pendingCap = false }
            }
        }
        text = capitalized

        // Capitalizar la primera letra de cada párrafo nuevo (\n\n)
        let paragraphs = text.components(separatedBy: "\n\n")
        text = paragraphs.enumerated().map { idx, para in
            guard idx > 0, let first = para.first, first.isLowercase else { return para }
            return para.prefix(1).uppercased() + para.dropFirst()
        }.joined(separator: "\n\n")

        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: – Cmd+V simulieren

    func simulatePaste() {
        if AXIsProcessTrusted() {
            // Primary: CGEvent — direct, synchronous, no extra process
            let src  = CGEventSource(stateID: .hidSystemState)
            let vKey: CGKeyCode = 9
            if let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
               let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
                down.flags = .maskCommand
                up.flags   = .maskCommand
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        } else {
            // No Accessibility permission yet: prompt the user and fall back to osascript.
            // osascript runs under its own process identity and may still succeed
            // while WisperBar's permission is being granted.
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e",
                "tell application \"System Events\" to keystroke \"v\" using command down"]
            try? task.run()
        }
    }
}

// MARK: – SFSpeechRecognizerDelegate

extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        guard !available, recordingState.isRecording else { return }
        // Erkennung kurz nicht verfügbar (z. B. Netz-Interruption) → neu starten statt Fehler
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isSessionActive else { return }
            self.restartSession()
        }
    }
}
