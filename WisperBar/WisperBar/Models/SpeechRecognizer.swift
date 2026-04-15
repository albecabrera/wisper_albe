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

    func stopRecording() {
        guard recordingState.isRecording else { return }
        endSession()
        recordingState = .idle
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
        copyToClipboard()
        NotificationCenter.default.post(name: .wbClosePopover, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.simulatePaste()
        }
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
        endSession()

        let inputNode = audioEngine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if #available(macOS 13, *), sfRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        recognitionTask = sfRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            DispatchQueue.main.async {
                // Callback ignorieren wenn Session bereits absichtlich beendet wurde
                // (z.B. durch stopRecording → endSession → recognitionTask.cancel())
                guard self.recognitionRequest != nil else { return }

                if let result {
                    if result.isFinal {
                        let text = result.bestTranscription.formattedString
                        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            self.transcript += (self.transcript.isEmpty ? "" : " ") + text
                        }
                        self.interimTranscript = ""
                    } else {
                        self.interimTranscript = result.bestTranscription.formattedString
                    }
                }

                if let error = error as NSError? {
                    // Stille Pausen und Abbrüche ignorieren
                    let ignoredCodes: Set<Int> = [
                        1110, 1107, 1101,  // kAFAssistantErrorDomain: no speech / silence
                        203, 209,          // Cancellation-Codes
                        -999,              // NSURLErrorCancelled
                    ]
                    let isBenign = ignoredCodes.contains(error.code) ||
                                   error.localizedDescription.lowercased().contains("cancel")
                    if !isBenign {
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

    private func endSession() {
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask   = nil

        DispatchQueue.main.async {
            self.audioLevels = Array(repeating: 0, count: self.barCount)
            self.interimTranscript = ""
        }
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

    // MARK: – Cmd+V simulieren

    private func simulatePaste() {
        // Accessibility-Erlaubnis prüfen (notwendig für CGEvent-Posting)
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: – SFSpeechRecognizerDelegate

extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        if !available && recordingState.isRecording {
            DispatchQueue.main.async {
                self.recordingState = .error("Spracherkennung momentan nicht verfügbar.")
                self.endSession()
            }
        }
    }
}
