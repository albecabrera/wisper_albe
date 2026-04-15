// WaveformView.swift
// Echtzeit-Wellenform-Visualisierung der Mikrofonpegel.
import SwiftUI

// MARK: – Live-Wellenform (während der Aufnahme)

struct WaveformView: View {

    let levels: [Float]

    var body: some View {
        Canvas { ctx, size in
            let count  = levels.count
            guard count > 0 else { return }

            let totalSpacing = CGFloat(count - 1) * 3
            let barWidth     = max(2, (size.width - totalSpacing) / CGFloat(count))
            let maxBarHeight = size.height * 0.9
            let centerY      = size.height / 2

            for i in 0..<count {
                let level  = CGFloat(levels[i])
                let barH   = max(3, level * maxBarHeight)
                let x      = CGFloat(i) * (barWidth + 3)
                let rect   = CGRect(
                    x: x,
                    y: centerY - barH / 2,
                    width: barWidth,
                    height: barH
                )

                // Farbe abhängig vom Pegel: leise = gedämpftes Grün, laut = helles Grün
                let green  = 0.55 + level * 0.35
                let opacity = 0.45 + level * 0.55
                let color  = Color(red: 0.09, green: green, blue: 0.35, opacity: opacity)

                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                ctx.fill(path, with: .color(color))
            }
        }
        .animation(.spring(response: 0.12, dampingFraction: 0.65), value: levels.map { $0 })
    }
}

// MARK: – Idle-Wellenform (sanfte Sinuswelle im Ruhezustand)

struct IdleWaveformView: View {

    @State private var phase: Double = 0

    private let barCount = 32
    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { ctx, size in
            let totalSpacing = CGFloat(barCount - 1) * 3
            let barWidth     = max(2, (size.width - totalSpacing) / CGFloat(barCount))
            let centerY      = size.height / 2

            for i in 0..<barCount {
                let t    = Double(i) / Double(barCount)
                let sine = sin(t * .pi * 3 + phase)
                let barH = max(3, CGFloat(16 + sine * 10))
                let x    = CGFloat(i) * (barWidth + 3)
                let rect = CGRect(
                    x: x,
                    y: centerY - barH / 2,
                    width: barWidth,
                    height: barH
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                ctx.fill(path, with: .color(Color.accentColor.opacity(0.22)))
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: 0.04)) { phase += 0.08 }
        }
    }
}

// MARK: – Pulsierende Aufnahme-Anzeige

struct RecordingDotView: View {

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.25))
                .frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.6 : 1.0)
                .opacity(pulsing ? 0 : 0.6)
                .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulsing)

            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .onAppear { pulsing = true }
    }
}

// MARK: – Countdown-Timer

struct RecordingTimerView: View {

    @State private var elapsed = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in elapsed += 1 }
    }

    private var formatted: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}
