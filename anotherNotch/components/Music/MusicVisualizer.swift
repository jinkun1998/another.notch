//
//  MusicVisualizer.swift
//  anotherNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import SwiftUI

struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let harmonics: [(CGFloat, CGFloat, Double, Double)] = [
        (0.22, 0.58, 2.1, 0.0), (0.36, 0.82, 2.7, 0.9), (0.48, 1.0, 3.4, 1.8),
        (0.48, 1.0, 3.6, 2.7), (0.34, 0.78, 2.6, 3.6), (0.20, 0.54, 2.0, 4.5)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: isPlaying && !reduceMotion ? 1.0 / 45.0 : nil, paused: !isPlaying)) { timeline in
            HStack(alignment: .center, spacing: 1) {
                ForEach(Array(harmonics.enumerated()), id: \.offset) { _, harmonic in
                    RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                        .fill(.white)
                        .frame(width: 1.5, height: 14 * level(for: harmonic, at: timeline.date))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 14)
        }
    }

    private func level(for harmonic: (CGFloat, CGFloat, Double, Double), at date: Date) -> CGFloat {
        guard isPlaying else { return 0.12 }
        guard !reduceMotion else { return 0.6 }

        let time = date.timeIntervalSinceReferenceDate
        let wave = (sin(time * harmonic.2 + harmonic.3) + cos(time * harmonic.2 * 0.58 + harmonic.3)) * 0.25 + 0.5
        return harmonic.0 + CGFloat(wave) * (harmonic.1 - harmonic.0)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 32, height: 16)
        .padding()
}
