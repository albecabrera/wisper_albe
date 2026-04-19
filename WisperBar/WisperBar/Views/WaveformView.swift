// WaveformView.swift
import SwiftUI

// MARK: – Live waveform (recording) – mirrored bars like pro audio software

struct WaveformView: View {

    let levels: [Float]

    var body: some View {
        Canvas { ctx, size in
            let count  = levels.count
            guard count > 0 else { return }

            let gap          = CGFloat(2.0)
            let totalSpacing = gap * CGFloat(count - 1)
            let barWidth     = max(1.5, (size.width - totalSpacing) / CGFloat(count))
            let maxHalf      = size.height * 0.46     // max bar arm from center
            let centerY      = size.height / 2

            for i in 0..<count {
                let level = CGFloat(levels[i])
                let arm   = max(2, level * maxHalf)

                // Upper bar
                let upper = CGRect(x: CGFloat(i) * (barWidth + gap),
                                   y: centerY - arm,
                                   width: barWidth, height: arm)
                // Lower reflection (slightly smaller, more transparent)
                let lower = CGRect(x: CGFloat(i) * (barWidth + gap),
                                   y: centerY,
                                   width: barWidth, height: arm * 0.55)

                let pathU = Path(roundedRect: upper, cornerRadius: barWidth / 2)
                let pathL = Path(roundedRect: lower, cornerRadius: barWidth / 2)

                let alpha = 0.30 + level * 0.70
                ctx.fill(pathU, with: .color(Color.accentColor.opacity(alpha)))
                ctx.fill(pathL, with: .color(Color.accentColor.opacity(alpha * 0.30)))
            }
        }
        .animation(.spring(response: 0.08, dampingFraction: 0.55), value: levels.map { $0 })
    }
}

// MARK: – Idle waveform (ambient double-sine)

struct IdleWaveformView: View {

    @State private var phase: Double = 0

    private let barCount = 48
    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { ctx, size in
            let gap          = CGFloat(2.0)
            let totalSpacing = gap * CGFloat(barCount - 1)
            let barWidth     = max(1.5, (size.width - totalSpacing) / CGFloat(barCount))
            let centerY      = size.height / 2

            for i in 0..<barCount {
                let t    = Double(i) / Double(barCount)
                let sine = sin(t * .pi * 5 + phase) * 0.55
                         + sin(t * .pi * 2.7 + phase * 0.6) * 0.45
                let arm  = max(2, CGFloat(10 + sine * 7))

                let upper = CGRect(x: CGFloat(i) * (barWidth + gap),
                                   y: centerY - arm,
                                   width: barWidth, height: arm)
                let lower = CGRect(x: CGFloat(i) * (barWidth + gap),
                                   y: centerY,
                                   width: barWidth, height: arm * 0.45)

                let path1 = Path(roundedRect: upper, cornerRadius: barWidth / 2)
                let path2 = Path(roundedRect: lower, cornerRadius: barWidth / 2)
                ctx.fill(path1, with: .color(Color.accentColor.opacity(0.20)))
                ctx.fill(path2, with: .color(Color.accentColor.opacity(0.06)))
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: 0.04)) { phase += 0.065 }
        }
    }
}

// MARK: – Pulsing recording dot

struct RecordingDotView: View {

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.20))
                .frame(width: 20, height: 20)
                .scaleEffect(pulsing ? 1.9 : 1.0)
                .opacity(pulsing ? 0 : 0.5)
                .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulsing)

            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .onAppear { pulsing = true }
    }
}

// MARK: – Recording timer

struct RecordingTimerView: View {

    @State private var elapsed = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in elapsed += 1 }
    }

    private var formatted: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}
