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
            let text = normalizeText(interimTranscript.trimmingCharacters(in: .whitespaces))
            if !text.isEmpty {
                transcript += (transcript.isEmpty ? "" : " ") + text
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
                            // Apple devolvió solo puntuación (ej: "." por "Punkt"):
                            // anexar al interim que tiene las palabras previas.
                            self.interimTranscript += text.trimmingCharacters(in: .whitespaces)
                        } else if text.count >= self.interimTranscript.count {
                            self.interimTranscript = text
                        }
                        // restartSession() vuelca interimTranscript → transcript
                        self.restartSession()
                        return
                    } else {
                        // Resultado parcial: solo sobreescribir si el nuevo texto
                        // tiene letras. Si Apple manda solo "." (por "Punkt"),
                        // anexar al interim existente para no borrar las palabras previas.
                        if text.rangeOfCharacter(from: .letters) != nil {
                            self.interimTranscript = text
                        } else {
                            self.interimTranscript += text.trimmingCharacters(in: .whitespaces)
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
        if !interimTranscript.isEmpty {
            transcript += (transcript.isEmpty ? "" : " ") + interimTranscript
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
        // "coma" / "Komma" → ","  |  "punto" / "Punkt" → "."
        let replacements: [(pattern: String, replacement: String)] = [
            // frases largas primero para que no sean procesadas por patrones más cortos
            (#"\s*\bpunto y aparte\b\s*"#,     "\n\n"),
            (#"\s*\b[Aa]bsatz\b\s*"#,          "\n\n"),
            (#"\s*\b[Kk]omma\b\s*"#,           ","),
            (#"\s*\bcoma\b\s*"#,               ","),
            (#"\s*\b[Pp]unkt\b\s*"#,           "."),
            (#"\s*\bpunto\b\s*"#,              "."),
        ]
        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
        }
        // Leerzeichen vor Satzzeichen entfernen, doppelte Satzzeichen reduzieren
        text = text.replacingOccurrences(of: " ,", with: ",")
        text = text.replacingOccurrences(of: " .", with: ".")
        if let regex = try? NSRegularExpression(pattern: #",+"#, options: []) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ",")
        }
        if let regex = try? NSRegularExpression(pattern: #"\.+"#, options: []) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ".")
        }
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
