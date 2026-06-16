import SwiftUI

// MARK: - PillWaveformState

/// Rolling level history for the recording pill waveform.
@MainActor
final class PillWaveformState: ObservableObject {
  // 14 slots — fewer bars, cleaner read.
  @Published var levels: [CGFloat] = Array(repeating: 0.04, count: 14)

  /// Set by the parent on every SwiftUI tick so the timer always has the latest value.
  var currentAudioLevel: Float = 0
  /// When true, ignore the mic level and animate a calm indeterminate "working" wave (transcribing).
  var processing = false

  private var phase: Double = 0
  private var timer: Timer?

  func startTimer() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.tick() }
    }
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  func reset() {
    levels = Array(repeating: 0.04, count: 14)
    phase = 0
  }

  private func tick() {
    phase += 0.18
    levels.removeFirst()
    if processing {
      // Smooth traveling wave — calm, clearly "working", no mic needed.
      levels.append(CGFloat(0.12 + 0.30 * (0.5 + 0.5 * sin(phase * 2))))
      return
    }
    let base = CGFloat(currentAudioLevel)
    let jitter = CGFloat.random(in: -0.04...0.04)
    levels.append(max(0.04, min(1.0, base + jitter)))
  }

  deinit { timer?.invalidate() }
}

// MARK: - PillWaveformView

/// Center-mirrored bar waveform for the recording pill.
///
/// 14 bars, uniform opacity — quiet and refined. Accent color at 0.75 opacity so
/// it reads clearly against both the Liquid Glass and the material fallback.
struct PillWaveformView: View {
  var audioLevel: Float
  var accentColor: Color
  var isProcessing: Bool = false

  @StateObject private var state = PillWaveformState()

  private let barCount = 14
  private let barWidth: CGFloat = 2.0
  private let barSpacing: CGFloat = 2.0
  private let maxHalfHeight: CGFloat = 11.0
  private let minHalfHeight: CGFloat = 1.5

  private var totalWidth: CGFloat {
    CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
  }

  var body: some View {
    Canvas { context, size in
      drawBars(in: context, size: size)
    }
    .frame(width: totalWidth, height: maxHalfHeight * 2)
    .onChange(of: audioLevel) { _, newLevel in
      state.currentAudioLevel = newLevel
    }
    .onChange(of: isProcessing) { _, newValue in
      state.processing = newValue
    }
    .onAppear {
      state.currentAudioLevel = audioLevel
      state.processing = isProcessing
      state.startTimer()
    }
    .onDisappear {
      state.stopTimer()
    }
  }

  // MARK: - Drawing

  private func drawBars(in context: GraphicsContext, size: CGSize) {
    let midY = size.height / 2
    let levels = state.levels

    for (index, level) in levels.enumerated() {
      let x = CGFloat(index) * (barWidth + barSpacing)
      let halfH = max(minHalfHeight, level * maxHalfHeight)
      let rect = CGRect(x: x, y: midY - halfH, width: barWidth, height: halfH * 2)

      let opacity = 0.4 + Double(level) * 0.45

      let path = Path { p in
        p.addRoundedRect(
          in: rect,
          cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
        )
      }
      context.fill(path, with: .color(accentColor.opacity(opacity)))
    }
  }
}
