'use strict';

// STATE
let recognition = null;
let isRecording = false;
let timerInterval = null;
let elapsedSeconds = 0;
let audioContext = null;
let analyser = null;
let microphone = null;
let animationId = null;
let mediaStream = null;

// DOM
const recBtn         = document.getElementById('recBtn');
const recIcon        = document.getElementById('recIcon');
const startBtn       = document.getElementById('startBtn');
const clearBtn       = document.getElementById('clearBtn');
const copyBtn        = document.getElementById('copyBtn');
const statusDot      = document.getElementById('statusDot');
const statusText     = document.getElementById('statusText');
const timerEl        = document.getElementById('timer');
const transcriptArea = document.getElementById('transcriptArea');
const interimText    = document.getElementById('interimText');
const waveCanvas     = document.getElementById('waveCanvas');
const waveformIdle   = document.getElementById('waveformIdle');
const cleanupToggle  = document.getElementById('cleanupToggle');
const autoStopToggle = document.getElementById('autoStopToggle');
const langSelect     = document.getElementById('langSelect');
const toast          = document.getElementById('toast');
const ctx2d          = waveCanvas.getContext('2d');

// ─── FILLER WORDS ─────────────────────────────────────────────────────────────
const FILLERS_DE = /\b(äh|ähem|öhm|öh|ähm|hm+|mhm|quasi quasi|also also)\b/gi;
const FILLERS_EN = /\b(uh+|um+|hmm+|er+|like like|you know you know)\b/gi;
const CORR_DE = /\b[\wÄÖÜäöüß][\wÄÖÜäöüß\s]{0,30}?,\s*(?:ne|nee|also|ich meine|ich meinte|eigentlich)\s+(.+?)(?=[,.]|$)/gi;
const CORR_EN = /\b\w[\w\s]{0,30}?,\s*(?:i mean|i meant|actually|no wait)\s+(.+?)(?=[,.]|$)/gi;

function cleanTranscript(text, lang) {
  if (!cleanupToggle.checked) return text;
  const fillers = lang.startsWith('de') ? FILLERS_DE : FILLERS_EN;
  const corrPat = lang.startsWith('de') ? CORR_DE : CORR_EN;
  text = text.replace(fillers, '');
  text = text.replace(corrPat, (_, corr) => corr);
  text = text.replace(/\s{2,}/g, ' ').trim();
  if (text.length > 0) text = text[0].toUpperCase() + text.slice(1);
  return text;
}

// ─── SPEECH RECOGNITION ──────────────────────────────────────────────────────
function initRecognition() {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) {
    showToast('Spracherkennung nicht verfügbar. Bitte Chrome nutzen.');
    return null;
  }
  const rec = new SR();
  rec.lang = langSelect.value;
  rec.continuous = true;
  rec.interimResults = true;
  rec.maxAlternatives = 1;

  rec.onstart = () => setRecordingState(true);

  rec.onresult = (e) => {
    let interim = '';
    let finalStr = '';
    for (let i = e.resultIndex; i < e.results.length; i++) {
      const t = e.results[i][0].transcript;
      if (e.results[i].isFinal) finalStr += t + ' ';
      else interim += t;
    }
    interimText.textContent = interim;
    if (finalStr) {
      const cleaned = cleanTranscript(finalStr, langSelect.value);
      if (cleaned) {
        const cur = transcriptArea.value;
        const sep = cur && !cur.endsWith(' ') && !cur.endsWith('\n') ? ' ' : '';
        transcriptArea.value = cur + sep + cleaned;
        transcriptArea.scrollTop = transcriptArea.scrollHeight;
      }
      interimText.textContent = '';
      if (autoStopToggle.checked) scheduleAutoStop();
    }
  };

  rec.onerror = (e) => {
    if (e.error === 'no-speech') return;
    if (e.error === 'not-allowed') showToast('Mikrofonzugriff verweigert.');
    else showToast('Fehler: ' + e.error);
    stopRecording();
  };

  rec.onend = () => {
    if (isRecording) { try { rec.start(); } catch {} }
    else setRecordingState(false);
  };

  return rec;
}

// AUTO-STOP
let autoStopTimeout = null;
function scheduleAutoStop() {
  clearTimeout(autoStopTimeout);
  autoStopTimeout = setTimeout(() => { if (isRecording) stopRecording(); }, 3000);
}

// ─── WAVEFORM ────────────────────────────────────────────────────────────────
async function startWaveform() {
  try {
    mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    audioContext = new (window.AudioContext || window.webkitAudioContext)();
    analyser = audioContext.createAnalyser();
    analyser.fftSize = 256;
    microphone = audioContext.createMediaStreamSource(mediaStream);
    microphone.connect(analyser);
    waveformIdle.style.display = 'none';
    waveCanvas.style.display = 'block';
    drawWaveform();
  } catch (_) { /* silent */ }
}

function drawWaveform() {
  if (!analyser) return;
  animationId = requestAnimationFrame(drawWaveform);
  const buf = new Uint8Array(analyser.frequencyBinCount);
  analyser.getByteFrequencyData(buf);
  const W = waveCanvas.width, H = waveCanvas.height;
  ctx2d.clearRect(0, 0, W, H);
  const count = 44;
  const bw = Math.floor(W / count) - 2;
  const sp = Math.floor(W / count);
  for (let i = 0; i < count; i++) {
    const v = buf[Math.floor((i / count) * buf.length)] / 255;
    const bh = Math.max(4, v * H * 0.9);
    ctx2d.fillStyle = `rgba(46,204,113,${0.4 + v * 0.6})`;
    const rx = Math.min(bw / 2, 3);
    roundRect(ctx2d, i * sp, (H - bh) / 2, bw, bh, rx);
    ctx2d.fill();
  }
}

function roundRect(c, x, y, w, h, r) {
  c.beginPath();
  c.moveTo(x + r, y);
  c.lineTo(x + w - r, y);
  c.quadraticCurveTo(x + w, y, x + w, y + r);
  c.lineTo(x + w, y + h - r);
  c.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  c.lineTo(x + r, y + h);
  c.quadraticCurveTo(x, y + h, x, y + h - r);
  c.lineTo(x, y + r);
  c.quadraticCurveTo(x, y, x + r, y);
  c.closePath();
}

function stopWaveform() {
  if (animationId) { cancelAnimationFrame(animationId); animationId = null; }
  if (microphone) { microphone.disconnect(); microphone = null; }
  if (audioContext) { audioContext.close(); audioContext = null; }
  if (mediaStream) { mediaStream.getTracks().forEach(t => t.stop()); mediaStream = null; }
  analyser = null;
  waveCanvas.style.display = 'none';
  waveformIdle.style.display = 'block';
  ctx2d.clearRect(0, 0, waveCanvas.width, waveCanvas.height);
}

// ─── TIMER ───────────────────────────────────────────────────────────────────
function startTimer() {
  elapsedSeconds = 0;
  timerEl.textContent = '00:00';
  timerInterval = setInterval(() => {
    elapsedSeconds++;
    const m = String(Math.floor(elapsedSeconds / 60)).padStart(2, '0');
    const s = String(elapsedSeconds % 60).padStart(2, '0');
    timerEl.textContent = `${m}:${s}`;
  }, 1000);
}
function stopTimer() { clearInterval(timerInterval); timerInterval = null; }

// ─── STATE ────────────────────────────────────────────────────────────────────
function setRecordingState(active) {
  isRecording = active;
  recBtn.classList.toggle('recording', active);
  statusDot.className = 'status-dot' + (active ? ' active' : ' done');
  statusText.textContent = active ? 'Aufnahme läuft…' : 'Fertig';
  recIcon.innerHTML = active
    ? `<rect x="6" y="6" width="10" height="10" rx="2"/>`
    : `<path d="M11 2a4 4 0 0 1 4 4v5a4 4 0 0 1-8 0V6a4 4 0 0 1 4-4z"/>
       <path d="M4.5 11a6.5 6.5 0 0 0 13 0h1.5a8 8 0 0 1-16 0H4.5z"/>`;
}

// ─── START / STOP ─────────────────────────────────────────────────────────────
async function startRecording() {
  if (isRecording) return;
  recognition = initRecognition();
  if (!recognition) return;
  await startWaveform();
  try {
    recognition.start();
    startTimer();
    interimText.textContent = '';
  } catch (err) {
    showToast('Start-Fehler: ' + err.message);
  }
}

function stopRecording() {
  if (!isRecording) return;
  isRecording = false;
  clearTimeout(autoStopTimeout);
  if (recognition) { recognition.stop(); recognition = null; }
  stopWaveform();
  stopTimer();
  interimText.textContent = '';
  setRecordingState(false);
}

function toggleRecording() {
  if (isRecording) stopRecording(); else startRecording();
}

// ─── COPY ─────────────────────────────────────────────────────────────────────
function copyText() {
  const text = transcriptArea.value.trim();
  if (!text) { showToast('Kein Text zum Kopieren.'); return; }
  navigator.clipboard.writeText(text)
    .then(() => showToast('Text kopiert!'))
    .catch(() => { transcriptArea.select(); document.execCommand('copy'); showToast('Text kopiert!'); });
}

// ─── TOAST ────────────────────────────────────────────────────────────────────
let toastTimer = null;
function showToast(msg) {
  toast.textContent = msg;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 3000);
}

// ─── EVENTS ───────────────────────────────────────────────────────────────────
recBtn.addEventListener('click', toggleRecording);
startBtn.addEventListener('click', () => {
  document.getElementById('app').scrollIntoView({ behavior: 'smooth' });
  setTimeout(startRecording, 400);
});
clearBtn.addEventListener('click', () => {
  transcriptArea.value = '';
  interimText.textContent = '';
  statusDot.className = 'status-dot';
  statusText.textContent = 'Bereit';
  timerEl.textContent = '00:00';
});
copyBtn.addEventListener('click', copyText);
langSelect.addEventListener('change', () => {
  if (recognition) recognition.lang = langSelect.value;
});

document.addEventListener('keydown', (e) => {
  const tag = document.activeElement.tagName;
  if (tag === 'TEXTAREA' || tag === 'INPUT' || tag === 'SELECT') return;
  if (e.code === 'Space') { e.preventDefault(); toggleRecording(); }
});

function resizeCanvas() {
  waveCanvas.width = waveCanvas.parentElement.clientWidth || 400;
}
window.addEventListener('resize', resizeCanvas);
resizeCanvas();
