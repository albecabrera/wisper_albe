#!/usr/bin/env python3
"""
WisperBar – lokale Spracheingabe als macOS Menüleisten-App
Shortcut: fn + Shift  (braucht Eingabeüberwachung in Systemeinstellungen)
"""

import threading
import time
import subprocess
import numpy as np
import sounddevice as sd
import pyperclip
import rumps
from faster_whisper import WhisperModel
from pynput import keyboard as kb
from AppKit import NSAttributedString, NSForegroundColorAttributeName, NSColor

try:
    import anthropic as _anthropic
    _ANTHROPIC_AVAILABLE = True
except ImportError:
    _ANTHROPIC_AVAILABLE = False

SAMPLE_RATE = 16_000
MODEL_SIZE  = "base"
LANGUAGES   = [
    ("🇩🇪", "Deutsch", "de"),
    ("🇺🇸", "English", "en"),
    ("🇪🇸", "Español", "es"),
]

# ── Whisper initial_prompt ────────────────────────────────────────────────────
# Texto de ejemplo que imita el dictado real con los comandos como palabras.
# Whisper lo trata como "contexto anterior" y aprende a mantener Komma/Punkt/etc.
# como palabras en la transcripción en lugar de convertirlos a símbolos.
INITIAL_PROMPTS = {
    "de": (
        "Guten Tag Komma ich diktiere jetzt diesen Text Punkt "
        "Ich benutze Komma für kurze Pausen Komma und Punkt um einen Satz zu beenden Punkt "
        "Mit Absatz beginne ich einen neuen Abschnitt Punkt "
        "Ausrufezeichen Fragezeichen Doppelpunkt Semikolon und Bindestrich "
        "sind weitere Befehle Punkt Neue Zeile macht einen einfachen Umbruch Punkt"
    ),
    "es": (
        "Buenos días coma voy a dictar este texto punto "
        "Uso coma para pausas coma y punto para terminar oraciones punto "
        "Con punto y aparte comienzo un nuevo párrafo punto "
        "Signo de exclamación signo de interrogación dos puntos "
        "punto y coma y guión son otros comandos punto "
        "Nueva línea hace un salto simple punto"
    ),
    "en": (
        "Hello comma I am dictating this text period "
        "I use comma for short pauses comma and period to end sentences period "
        "With new paragraph I start a new section period "
        "Exclamation mark question mark colon semicolon and hyphen "
        "are further commands period New line creates a simple line break period"
    ),
}

# ── Claude system prompts ─────────────────────────────────────────────────────
# Usados para post-procesar el texto crudo de Whisper vía Claude API.
# Cada prompt convierte los comandos de voz en puntuación real y aplica
# capitalización correcta según las reglas del idioma.
CLAUDE_SYSTEM_PROMPTS = {
    "de": """\
Du bist ein Diktat-Nachbearbeitungsassistent. Du erhältst rohes Whisper-Transkript \
auf Deutsch, in dem der Sprecher Satzzeichen durch gesprochene Befehle angibt. \
Deine einzige Aufgabe ist die Umwandlung in korrekt formatierten Text.

BEFEHLSZUORDNUNG:
• Komma → ,
• Punkt → .
• Ausrufezeichen → !
• Fragezeichen → ?
• Doppelpunkt → :
• Semikolon / Strichpunkt → ;
• Bindestrich → -
• Absatz / Neuer Absatz → [zwei Zeilenumbrüche, d. h. neuer Absatz]
• Neue Zeile / Zeilenumbruch → [ein Zeilenumbruch]

FORMATIERUNGSREGELN:
1. Nach Punkt, Ausrufezeichen oder Fragezeichen: erstes Wort des nächsten Satzes \
großschreiben (sofern nicht bereits groß).
2. Nach Komma: Satz läuft weiter, kein Großbuchstabe.
3. Nach Absatz: erstes Wort des neuen Absatzes großschreiben.
4. Kein Leerzeichen vor Satzzeichen einfügen.
5. Mehrfach aufeinanderfolgende gleiche Satzzeichen auf eines reduzieren.
6. Mehrere Absatz-Befehle hintereinander: auf einen Absatzumbruch reduzieren.
7. Originalwörter des Sprechers vollständig erhalten – nichts hinzufügen, \
kürzen oder umformulieren.
8. Nur den fertigen Text ausgeben – keinerlei Erklärungen oder Kommentare.\
""",

    "es": """\
Eres un asistente de posprocesamiento de dictado. Recibes transcripciones brutas \
de Whisper en español donde el hablante indica la puntuación mediante comandos de voz. \
Tu única tarea es convertirlas en texto correctamente formateado.

MAPA DE COMANDOS:
• coma → ,
• punto → .
• signo de exclamación → !
• signo de interrogación → ?
• dos puntos → :
• punto y coma → ;
• guión → -
• punto y aparte / párrafo nuevo → [dos saltos de línea, es decir, párrafo nuevo]
• nueva línea / salto de línea → [un salto de línea]

REGLAS DE FORMATO:
1. Tras punto, signo de exclamación o signo de interrogación: capitalizar la primera \
letra de la siguiente oración (si no lo está ya).
2. Tras coma: la oración continúa, no capitalizar.
3. Tras punto y aparte: capitalizar la primera palabra del nuevo párrafo.
4. Ningún espacio antes de los signos de puntuación.
5. Signos duplicados consecutivos reducirlos a uno.
6. Múltiples "punto y aparte" seguidos: reducir a un único salto de párrafo.
7. Conservar íntegramente las palabras del hablante – no añadir, acortar \
ni reformular el contenido.
8. Devolver únicamente el texto formateado – sin explicaciones ni comentarios.\
""",

    "en": """\
You are a dictation post-processing assistant. You receive raw Whisper transcripts \
in English where the speaker indicates punctuation through spoken commands. \
Your only task is to convert them into correctly formatted text.

COMMAND MAP:
• comma → ,
• period / full stop → .
• exclamation mark / exclamation point → !
• question mark → ?
• colon → :
• semicolon → ;
• hyphen / dash → -
• new paragraph / paragraph break → [two line breaks, i.e. a new paragraph]
• new line / line break → [one line break]

FORMATTING RULES:
1. After period, exclamation mark, or question mark: capitalize the first letter \
of the next sentence (if not already capitalized).
2. After comma: sentence continues, do not capitalize.
3. After new paragraph: capitalize the first word of the new paragraph.
4. No space before punctuation marks.
5. Consecutive duplicate punctuation marks reduce to one.
6. Multiple "new paragraph" commands in a row: reduce to a single paragraph break.
7. Preserve the speaker's words in full – do not add, shorten, or rephrase content.
8. Output only the formatted text – no explanations or comments.\
""",
}


class WisperBar(rumps.App):

    def __init__(self):
        super().__init__("🔴 🎙", quit_button=None)

        self.recording  = False
        self.frames     = []
        self.transcript = ""
        self.lang_code  = "de"
        self._held      = set()
        self.model      = None

        self._build_menu()
        threading.Thread(target=self._load_model, daemon=True).start()

        try:
            self._listener = kb.Listener(
                on_press=self._key_press,
                on_release=self._key_release,
            )
            self._listener.daemon = True
            self._listener.start()
        except Exception:
            self._listener = None

    # ── Menü ─────────────────────────────────────────────────────────────────

    def _build_menu(self):
        self.btn_record = rumps.MenuItem("⏺  Aufnehmen", callback=self.toggle)
        self.lbl_status = rumps.MenuItem("⏳  Modell wird geladen…")
        self.btn_copy   = rumps.MenuItem("  Kopieren",  callback=self.copy)
        self.btn_paste  = rumps.MenuItem("  Einfügen",  callback=self.paste)
        self.btn_clear  = rumps.MenuItem("  Löschen",   callback=self.clear)

        # Sprachen direkt im Menü (kein Untermenü)
        self.lang_items = []
        for flag, name, code in LANGUAGES:
            item = rumps.MenuItem(f"   {flag}  {name}", callback=self._set_lang)
            item._lang_code = code
            item._lang_flag = flag
            item._lang_name = name
            self.lang_items.append(item)

        self.menu = [
            self.btn_record,
            None,
            self.lbl_status,
            None,
            self.btn_copy,
            self.btn_paste,
            self.btn_clear,
            None,
            *self.lang_items,
            None,
            rumps.MenuItem("Beenden", callback=lambda _: rumps.quit_application()),
        ]
        self._refresh_actions()
        for item in self.lang_items:
            self._apply_lang_style(item, item._lang_code == self.lang_code)

    # ── Modell laden ──────────────────────────────────────────────────────────

    def _load_model(self):
        try:
            self.model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")
            self.lbl_status.title = "✅  Bereit  –  fn + Shift"
        except Exception as e:
            self.lbl_status.title = f"❌  {e}"

    # ── Aufnahme ──────────────────────────────────────────────────────────────

    def toggle(self, _=None):
        if self.model is None:
            rumps.alert("Bitte warten", "Das Sprachmodell wird noch geladen.")
            return
        if self.recording:
            self._stop()
        else:
            self._start()

    def _start(self):
        self.recording        = True
        self.frames           = []
        self.transcript       = ""          # jede Aufnahme beginnt frisch
        self.title            = "🔴"
        self.btn_record.title = "⏹  Stopp"
        self.lbl_status.title = "●  Aufnahme läuft…"
        self._refresh_actions()
        threading.Thread(target=self._record_loop, daemon=True).start()

    def _record_loop(self):
        with sd.InputStream(
            samplerate=SAMPLE_RATE, channels=1, dtype="float32",
            callback=lambda data, *_: self.frames.append(data.copy()),
        ):
            while self.recording:
                time.sleep(0.05)

    def _stop(self):
        self.recording        = False
        self.title            = "⏳"
        self.btn_record.title = "⏺  Aufnehmen"
        self.lbl_status.title = "⏳  Transkription läuft…"
        threading.Thread(target=self._transcribe, daemon=True).start()

    # ── Transkription ─────────────────────────────────────────────────────────

    @staticmethod
    def _normalize_text(text):
        import re
        # Aplanar cualquier \n que Whisper inserte por su cuenta, para que
        # solo nuestros comandos explícitos creen párrafos nuevos.
        text = re.sub(r'[ \t\r\n]+', ' ', text).strip()
        text = re.sub(r'\bpunto y aparte\b', '\n\n', text, flags=re.IGNORECASE)
        text = re.sub(r'\b[Aa]bsatz\b',      '\n\n', text)
        text = re.sub(r'\b[Kk]omma\b',       ',',    text)
        text = re.sub(r'\bcoma\b',            ',',    text, flags=re.IGNORECASE)
        text = re.sub(r'\b[Pp]unto\b',        '.',    text)
        text = re.sub(r'\b[Pp]unkt\b',        '.',    text)
        text = re.sub(r',\s*,+',        ',', text)
        text = re.sub(r'\.(\s*\.)+',    '.', text)
        # Capitalizar la primera letra de cada párrafo nuevo
        parts = text.split('\n\n')
        text = '\n\n'.join(
            (p[0].upper() + p[1:] if p and p[0].islower() else p)
            for p in parts
        )
        return text

    def _post_process_with_claude(self, raw_text: str) -> str:
        """Post-procesa el texto crudo de Whisper con Claude API.
        Devuelve el texto formateado, o raw_text si la API falla."""
        if not _ANTHROPIC_AVAILABLE:
            return self._normalize_text(raw_text)
        try:
            client = _anthropic.Anthropic()
            msg = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=2048,
                system=CLAUDE_SYSTEM_PROMPTS.get(
                    self.lang_code,
                    CLAUDE_SYSTEM_PROMPTS["en"],
                ),
                messages=[{"role": "user", "content": raw_text}],
            )
            return msg.content[0].text.strip()
        except Exception:
            return self._normalize_text(raw_text)

    def _transcribe(self):
        if not self.frames:
            self.title = "🔴 🎙"
            self.lbl_status.title = "✅  Bereit  –  fn + Shift"
            return

        audio = np.concatenate(self.frames).flatten()
        segs, _ = self.model.transcribe(
            audio,
            language=self.lang_code,
            beam_size=5,
            initial_prompt=INITIAL_PROMPTS.get(self.lang_code, ""),
            condition_on_previous_text=False,
        )
        raw = " ".join(s.text.strip() for s in segs).strip()
        text = self._post_process_with_claude(raw)

        self.transcript = text
        self.title = "🎤"

        if text:
            pyperclip.copy(text)
            preview = (text[:45] + "…") if len(text) > 45 else text
            self.lbl_status.title = f'📝  "{preview}"'
            self._paste_to_active_app()
        else:
            self.lbl_status.title = "✅  Bereit  –  fn + Shift"

        self._refresh_actions()

    # ── Aktionen ──────────────────────────────────────────────────────────────

    def copy(self, _=None):
        if self.transcript:
            pyperclip.copy(self.transcript)

    def paste(self, _=None):
        if self.transcript:
            pyperclip.copy(self.transcript)
            threading.Thread(target=self._paste_to_active_app, daemon=True).start()

    def clear(self, _=None):
        self.transcript = ""
        self.lbl_status.title = "✅  Bereit  –  fn + Shift"
        self._refresh_actions()

    def _paste_to_active_app(self):
        time.sleep(0.35)
        try:
            ctrl = kb.Controller()
            with ctrl.pressed(kb.Key.cmd):
                ctrl.tap("v")
        except Exception:
            subprocess.run(
                ["osascript", "-e",
                 'tell application "System Events" to keystroke "v" using command down'],
                capture_output=True,
            )

    # ── Sprache ───────────────────────────────────────────────────────────────

    def _apply_lang_style(self, item, active):
        title = f"【{item._lang_flag}  {item._lang_name}】" if active else f"   {item._lang_flag}  {item._lang_name}"
        if active:
            attrs = {NSForegroundColorAttributeName: NSColor.redColor()}
            item._menuitem.setAttributedTitle_(
                NSAttributedString.alloc().initWithString_attributes_(title, attrs)
            )
        else:
            item._menuitem.setAttributedTitle_(None)
            item.title = title

    def _set_lang(self, sender):
        self.lang_code = sender._lang_code
        for item in self.lang_items:
            self._apply_lang_style(item, item._lang_code == self.lang_code)

    # ── fn + Shift Erkennung ──────────────────────────────────────────────────

    def _key_press(self, key):
        self._held.add(key)
        if self._is_fn_shift():
            self._held.clear()
            threading.Thread(
                target=lambda: (time.sleep(0.02), self.toggle()), daemon=True
            ).start()

    def _key_release(self, key):
        self._held.discard(key)

    def _is_fn_shift(self):
        shift = any(k in self._held for k in (kb.Key.shift, kb.Key.shift_l, kb.Key.shift_r))
        fn    = any(self._key_is_fn(k) for k in self._held)
        return shift and fn

    @staticmethod
    def _key_is_fn(key):
        if key == kb.Key.fn:
            return True
        try:
            return key.vk == 63
        except AttributeError:
            return False

    # ── UI-Hilfe ──────────────────────────────────────────────────────────────

    def _refresh_actions(self):
        has = bool(self.transcript)
        self.btn_copy.title  = "  Kopieren" if has else "  Kopieren   (kein Text)"
        self.btn_paste.title = "  Einfügen" if has else "  Einfügen   (kein Text)"
        self.btn_clear.title = "  Löschen"  if has else "  Löschen    (kein Text)"


if __name__ == "__main__":
    WisperBar().run()
